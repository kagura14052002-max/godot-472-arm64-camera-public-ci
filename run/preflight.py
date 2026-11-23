#!/usr/bin/env python3
"""Reject non-allowlisted files and recognizable credentials before downloading any source."""
from pathlib import Path
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {
    ".github/workflows/arm64-build.yml",
    "README.md",
    "patches/godot-4.7.2-camera-scandir-guard.patch",
    "qa/camera/camera_probe.gd",
    "qa/camera/project.godot",
    "qa/import/main.tscn",
    "qa/import/project.godot",
    "run/build_and_qa.sh",
    "run/deny_dev_scandir.c",
    "run/preflight.py",
}
PATTERNS = {
    "private_key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
    "aws_key": re.compile(r"AKIA[0-9A-Z]{16}"),
    "github_token": re.compile(r"gh[pousr]_[A-Za-z0-9_]{25,}"),
    "google_key": re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    "slack_key": re.compile(r"xox[baprs]-[A-Za-z0-9-]{15,}"),
}

def check():
    if (ROOT / "artifacts").exists():
        raise RuntimeError("Preexisting artifacts not allowed")
    found = set()
    for p in ROOT.rglob("*"):
        name = p.relative_to(ROOT).as_posix()
        if name == ".git" or name.startswith(".git/"):
            continue
        if p.is_symlink():
            raise RuntimeError("Symlink not allowed: " + name)
        if p.is_file():
            found.add(name)
            blob = p.read_bytes()
            if len(blob) > 100_000 or b"\0" in blob:
                raise RuntimeError("Oversized or non-text file: " + name)
            content = blob.decode("utf-8", errors="strict")
            for label, regex in PATTERNS.items():
                if regex.search(content):
                    raise RuntimeError("Sensitive pattern: " + label + " in " + name)
    if found != ALLOWED:
        raise RuntimeError("Unexpected/missing files: extra=" + str(sorted(found-ALLOWED)) + " missing=" + str(sorted(ALLOWED-found)))
    patch = (ROOT / "patches/godot-4.7.2-camera-scandir-guard.patch").read_text()
    if patch.count("diff --git ") != 1 or not patch.startswith("diff --git a/modules/camera/camera_linux.cpp b/modules/camera/camera_linux.cpp"):
        raise RuntimeError("Unexpected patch scope")
    if "struct dirent **devices = nullptr;" not in patch or "+\t\t\t\tfree(devices);" not in patch:
        raise RuntimeError("Camera fix missing")
    print("PREFLIGHT_PASS", len(found), "allowlisted files")
    print("PATCH_SHA256", hashlib.sha256(patch.encode()).hexdigest())

if __name__ == "__main__":
    try:
        check()
    except Exception as e:
        print("PREFLIGHT_BLOCKED", str(e), file=sys.stderr)
        sys.exit(1)
