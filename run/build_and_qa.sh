#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PACKAGE="$PWD"
python3 run/preflight.py
if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "HOLD: native ARM64 builder is required" >&2; exit 41
fi
for program in gcc g++ scons curl sha256sum tar git readelf timeout; do
  command -v "$program" >/dev/null || { echo "HOLD: missing tool $program" >&2; exit 42; }
done
# CI VM must not contain private GODOT project data. Only the public Godot
# source archive is downloaded, after the strict allowlist/secret scan.
SOURCE_SHA="a18ce0ccec3ecc40b0dd6c4f5132ca934e9fb7c2979717940ff32aee1eb35481"
SOURCE_URL="https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/godot-4.7.2-stable.tar.xz"
mkdir -p artifacts
RUN_ROOT="$(mktemp -d -t grace-godot-arm64-XXXXXXXX)"
trap 'rm -rf -- "$RUN_ROOT"' EXIT
curl --fail --location --show-error --silent --retry 3 --output "$RUN_ROOT/source.tar.xz" "$SOURCE_URL"
printf '%s  %s\n' "$SOURCE_SHA" "$RUN_ROOT/source.tar.xz" | sha256sum --check --status || {
  echo 'HOLD: Godot source release SHA256 mismatch' >&2; exit 43;
}
mkdir "$RUN_ROOT/source"
tar -xJf "$RUN_ROOT/source.tar.xz" --strip-components=1 -C "$RUN_ROOT/source"
cd "$RUN_ROOT/source"
python3 - <<'PY_BLOB'
from pathlib import Path
import hashlib
p=Path('modules/camera/camera_linux.cpp')
b=p.read_bytes()
blob_sha=hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
if blob_sha != '0880bf9e0706d6d1def46ed52c57e9d244e95a35':
    raise SystemExit('HOLD: release camera source does not match pinned Godot commit')
print('UPSTREAM_CAMERA_BLOB_SHA_OK')
PY_BLOB
# Source release tarball may not include a .git directory. git apply still
# works as a plain patch tool and does not touch the original GODOT source.
git apply --check "$PACKAGE/patches/godot-4.7.2-camera-scandir-guard.patch"
git apply "$PACKAGE/patches/godot-4.7.2-camera-scandir-guard.patch"
python3 - <<'PY_CHECK'
from pathlib import Path
s=Path('modules/camera/camera_linux.cpp').read_text()
assert 'struct dirent **devices = nullptr;' in s
pos=s.index('int count = scandir("/dev"')
end=s.index('call_deferred("emit_signal"',pos)
branch=s[pos:end]
assert branch.count('free(devices);')==1
assert 'free(device);' in branch
print('PATCH_SOURCE_CHECK_OK')
PY_CHECK
# Diagnostic native ARM64 build: no release/bitwise parity claim.
# Full LTO is intentionally disabled for this diagnostic build.
scons -j2 platform=linuxbsd arch=arm64 target=editor \
  production=no optimize=speed_trace lto=none debug_symbols=yes \
  accesskit=no
mapfile -t bins < <(find bin -maxdepth 1 -type f -name 'godot.linuxbsd.editor.arm64*' | sort)
if (( ${#bins[@]} != 1 )); then echo "HOLD: expected 1 ARM64 editor, found ${#bins[@]}" >&2; exit 44; fi
ENGINE="$RUN_ROOT/source/${bins[0]}"
readelf -h "$ENGINE" | grep -Eq 'Machine:[[:space:]]*AArch64' || { echo 'HOLD: non-AArch64 output' >&2; exit 45; }
readelf -SW "$ENGINE" | grep -q '.debug_info' || { echo 'HOLD: missing DWARF debug symbols' >&2; exit 46; }
mkdir -p "$RUN_ROOT/qa/camera" "$RUN_ROOT/qa/import"
cp "$PACKAGE/qa/camera/"* "$RUN_ROOT/qa/camera/"
cp "$PACKAGE/qa/import/"* "$RUN_ROOT/qa/import/"
gcc -fPIC -shared -o "$RUN_ROOT/deny_dev_scandir.so" "$PACKAGE/run/deny_dev_scandir.c" -ldl
"$ENGINE" --version | tee "$PACKAGE/artifacts/version.txt"
for i in 1 2 3; do
  timeout 45s env LD_PRELOAD="$RUN_ROOT/deny_dev_scandir.so" \
    "$ENGINE" --headless --path "$RUN_ROOT/qa/camera" --script res://camera_probe.gd \
    >"$PACKAGE/artifacts/camera_${i}.log" 2>&1
  grep -q 'CAMERA_SCAN_TEST_START' "$PACKAGE/artifacts/camera_${i}.log"
  grep -q 'GODOT_DENY_DEV_SCANDIR_TEST_INJECTED' "$PACKAGE/artifacts/camera_${i}.log"
  grep -q 'CAMERA_SCAN_TEST_END' "$PACKAGE/artifacts/camera_${i}.log"
  if grep -E 'handle_crash|SIGSEGV|SCRIPT ERROR:|ERROR:' "$PACKAGE/artifacts/camera_${i}.log"; then
     echo "HOLD: camera scenario $i has errors" >&2; exit 47
  fi
done
# Clean import in a separate empty project. No GODOT-ZERO game source.
timeout 180s "$ENGINE" --headless --editor --import --path "$RUN_ROOT/qa/import" \
   >"$PACKAGE/artifacts/import.log" 2>&1
if grep -E 'handle_crash|SIGSEGV|SCRIPT ERROR:|ERROR:' "$PACKAGE/artifacts/import.log"; then
  echo 'HOLD: empty-project import failed' >&2; exit 48
fi
cp -n "$ENGINE" "$PACKAGE/artifacts/Godot_4.7.2_ARM64_camera_fixed_candidate"
sha256sum "$PACKAGE/artifacts/Godot_4.7.2_ARM64_camera_fixed_candidate" > "$PACKAGE/artifacts/SHA256SUMS"
printf 'source_sha256=%s\nsource_commit=%s\nbuild_type=native_ARM64_diagnostic_optimized_O2_no_LTO\n' \
  "$SOURCE_SHA" "ed1daf0bf001b61586d9930840f2f1394092c079" \
  > "$PACKAGE/artifacts/BUILD_METADATA.txt"
echo 'BUILD_AND_QA_PASS (native ARM64 builder)'
