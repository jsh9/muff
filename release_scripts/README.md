# Muff Release Scripts

This folder contains platform-specific scripts to build wheels and standalone binaries for Muff, and optionally publish artifacts to PyPI and attach them to a GitHub Release.

Provided scripts
- `step-1-build-macos.sh`: Build on macOS ARM64 (Apple Silicon).
- `step-1-build-linux.sh`: Build on Linux (x86_64 or ARM64; choose via `--arch`).
- `step-1-build-windows.ps1`: Build on Windows x86_64 (PowerShell).
- `step-2-create-github-release.sh`: Create/update a GitHub release and upload archives.
- `step-3-publish-to-pypi.sh`: Publish wheels/sdists to PyPI.

Artifacts produced (step 1)
- Wheels under `dist/` for package `muff` (module and binary name remain `ruff`).
- Standalone binary archives: `ruff-<target>.tar.gz` (Linux/macOS) or `ruff-<target>.zip` (Windows) plus a `.sha256` checksum.

Prerequisites
- Python (via Anaconda):
  - Create/activate an environment (Python 3.10+ recommended):
    - `conda create -n muff-release python=3.11 -y`
    - `conda activate muff-release`
  - Upgrade packaging tools: `python -m pip install -U pip wheel setuptools`
  - Install `maturin` (required) and optionally `twine` (for PyPI):
    - `pip install maturin>=1.9,<2 twine`
- Rust toolchain:
  - Install `rustup` and the toolchain pinned by `rust-toolchain.toml` (rustup respects this automatically).
  - Ensure `cargo` works in your shell.
- GitHub CLI (optional for releases):
  - `gh auth login` (set to your Muff repo).
- Platform-specific utilities:
  - macOS: `shasum` (preinstalled), `tar`.
- Linux: `sha256sum`, `tar`. For manylinux wheels, Docker is recommended. The Linux build script uses the manylinux2014 images (`quay.io/pypa/manylinux2014_x86_64` and `quay.io/pypa/manylinux2014_aarch64`) with `--compatibility manylinux_2_17` to target glibc 2.17.
  - Windows: PowerShell 5+, `Compress-Archive`, `Get-FileHash` (built-in). Optionally `Set-ExecutionPolicy Bypass` to run the script.

Environment variables (optional)
- `PACKAGE_NAME` (default: `muff`)
- `MODULE_NAME` (default: `ruff`)
- `BINARY_NAME` (default: `ruff`)
- `ARCHIVE_PREFIX` (default: `ruff`)

Flags
- Step 1 (build scripts):
  - macOS: `--sdist` (also build sdist; use once per release)
  - Linux: `--arch x86_64|aarch64`, `--sdist`
- Step 2 (GitHub release):
  - `--tag vX.Y.Z` (required)
  - `--assets <file ...>` (optional; defaults to `ruff-*.tar.gz`, `ruff-*.zip` and their `.sha256`)
- Step 3 (PyPI):
  - `--path dist` (directory to upload from)
  - `--include-sdist` (include sdists in upload)

Recommended flow
1) Build artifacts on each platform
   - macOS ARM64:
     - `chmod +x release_scripts/step-1-build-macos.sh`
     - `release_scripts/step-1-build-macos.sh --sdist`
   - Linux x86_64 (on x86_64 Ubuntu):
     - `chmod +x release_scripts/step-1-build-linux.sh`
     - `release_scripts/step-1-build-linux.sh --arch x86_64 --sdist`
   - Linux ARM64 (on ARM Ubuntu):
     - `release_scripts/step-1-build-linux.sh --arch aarch64`
   - Windows x86_64:
     - `powershell -ExecutionPolicy Bypass -File release_scripts/step-1-build-windows.ps1`

2) Create/Update GitHub release (on macOS)
   - `chmod +x release_scripts/step-2-create-github-release.sh`
   - `release_scripts/step-2-create-github-release.sh --tag v0.12.12-muff1`

3) Publish to PyPI (on macOS)
   - `chmod +x release_scripts/step-3-publish-to-pypi.sh`
   - `release_scripts/step-3-publish-to-pypi.sh --path dist --include-sdist`

Notes
- The build scripts call `python scripts/transform_readme.py --target pypi` to prepare the PyPI README.
- Only one platform needs to build the sdist; use `--sdist` once.
- Manylinux wheels are built against manylinux2014 with `--compatibility manylinux_2_17` for maximum glibc compatibility (2.17). Docker must be available to use the `quay.io/pypa/manylinux2014_*` images.
- Ensure you’re logged into GitHub (`gh auth login`) and PyPI (`twine` or `maturin` configured) before steps 2 and 3.
