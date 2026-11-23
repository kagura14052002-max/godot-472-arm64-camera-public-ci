# Godot 4.7.2 ARM64 camera source-fix CI

Public build-only scripts and an upstream-source patch for the Godot 4.7.2 Linux ARM64 camera `scandir("/dev")` error. No game source, private repository contents, credentials, keys, or binaries are included.

- Upstream pinned commit: `ed1daf0bf001b61586d9930840f2f1394092c079`.
- Official public source archive SHA-256: `a18ce0ccec3ecc40b0dd6c4f5132ca934e9fb7c2979717940ff32aee1eb35481`.
- Engine is built natively on `ubuntu-24.04-arm`, with diagnostic DWARF debug symbols, no LTO and no AccessKit dependency.
- `run/preflight.py` strictly rejects any file beyond the 10 published text files and scans for recognizable credentials.
- `run/build_and_qa.sh` verifies the downloaded public source hash, applies only the camera source patch, compiles and checks camera and empty-project import.
- The original Godot executable is never replaced. Any newly compiled engine is an independent candidate.

Run the GitHub Actions workflow manually with `build=false` to probe the free native ARM64 runner, or `build=true` after the probe passes. This repository intentionally does not enable automatic push-triggered builds.
