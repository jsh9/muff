# Release Instructions

This document explains how to create a new release of Muff and publish it to GitHub and PyPI.

## 1. Overview

The release process consists of these steps:
1. **Build** - Create wheels and binaries for target platforms
2. **GitHub Release** - Create a GitHub release with artifacts
3. **PyPI Publish** - Upload wheels to PyPI

## 2. Prerequisites

### 2.1 Required Tools
- **Python 3** with `pip`
- **Rust/Cargo** (for building)
- **GitHub CLI** (`brew install gh`) for releases
- **uv** (auto-installed by scripts) for PyPI publishing

### 2.2 Optional Cross-compilation Tools
For building Linux and Windows binaries from macOS:
```bash
# Option 1: Use cargo-cross (recommended)
cargo install cross

# Option 2: Install cross-compilation toolchains
brew install messense/macos-cross-toolchains/x86_64-unknown-linux-gnu
brew install messense/macos-cross-toolchains/aarch64-unknown-linux-gnu
brew install mingw-w64  # for Windows
```

### 2.3 Authentication Setup
```bash
# GitHub CLI authentication
gh auth login

# PyPI authentication (if not using trusted publishing)
# Set up API token in ~/.pypirc or use uv's authentication
```

## 3. Release Scripts

### 3.1 `step-0-local-release.sh` - Main Script (Recommended)
Orchestrates the entire release process with options to skip steps.

**Usage:**
```bash
./release/step-0-local-release.sh v1.0.0
./release/step-0-local-release.sh v1.0.0 --skip-pypi        # Only GitHub release
./release/step-0-local-release.sh v1.0.0 --skip-github     # Only PyPI
./release/step-0-local-release.sh v1.0.0 --skip-build      # Use existing builds
```

### 3.2 Individual Build Scripts
Run these if you want to build for specific platforms only:

#### 3.2.1 `step-1-build-macos.sh`
Builds for macOS (both Intel and Apple Silicon):
```bash
./release/step-1-build-macos.sh
```
**Outputs:**
- `dist/*.whl` - Python wheels
- `muff-aarch64-apple-darwin.tar.gz` - Apple Silicon binary
- `muff-x86_64-apple-darwin.tar.gz` - Intel binary

#### 3.2.2 `step-1-build-linux.sh`
Cross-compiles for Linux:
```bash
./release/step-1-build-linux.sh
```
**Outputs:**
- `muff-x86_64-unknown-linux-gnu.tar.gz` - Linux x64 binary
- `muff-aarch64-unknown-linux-gnu.tar.gz` - Linux ARM64 binary

#### 3.2.3 `step-1-build-windows.sh`
Cross-compiles for Windows:
```bash
./release/step-1-build-windows.sh
```
**Outputs:**
- `muff-x86_64-pc-windows-gnu.zip` - Windows x64 binary
- `muff-x86_64-pc-windows-msvc.zip` - Windows MSVC binary

### 3.3 `step-2-create-release.sh`
Creates GitHub release with all artifacts:
```bash
./release/step-2-create-release.sh v1.0.0
```

### 3.4 `step-3-publish-pypi.sh`
Publishes wheels to PyPI:
```bash
./release/step-3-publish-pypi.sh
```

## 4. Complete Release Workflow

### 4.1 Method 1: All-in-One (Recommended)
```bash
# Full release to both GitHub and PyPI
./release/step-0-local-release.sh v1.0.0
```

### 4.2 Method 2: Step-by-Step
```bash
# 1. Build for your platform
./release/step-1-build-macos.sh

# 2. (Optional) Build for other platforms
./release/step-1-build-linux.sh
./release/step-1-build-windows.sh

# 3. Create GitHub release
./release/step-2-create-release.sh v1.0.0

# 4. Publish to PyPI
./release/step-3-publish-pypi.sh
```

## 5. Version Naming Convention

Use semantic versioning with a `v` prefix:
- `v1.0.0` - Major release
- `v1.1.0` - Minor release
- `v1.0.1` - Patch release
- `v1.0.0-beta.1` - Pre-release

**Examples:**
```bash
./release/step-0-local-release.sh v1.0.0           # Stable release
./release/step-0-local-release.sh v1.0.0-beta.1    # Pre-release
./release/step-0-local-release.sh v2.0.0-alpha.1   # Alpha release
```

## 6. Pre-Release Considerations

- The scripts will prompt before publishing pre-releases to PyPI
- Pre-releases are marked appropriately on GitHub
- Version tags must follow the format: `vX.Y.Z` or `vX.Y.Z-suffix`

## 7. Outputs

After a successful release:

### 7.1 GitHub Release
- **URL**: `https://github.com/your-username/muff/releases/tag/v1.0.0`
- **Contents**: Binaries, wheels, checksums, and release notes

### 7.2 PyPI Package
- **URL**: `https://pypi.org/project/muff/`
- **Install**: `pip install muff`

### 7.3 Local Artifacts
- `dist/*.whl` - Python wheels
- `dist/*.tar.gz` - Source distribution
- `*.tar.gz` / `*.zip` - Binary archives with checksums

## 8. Troubleshooting

### 8.1 Cross-compilation Issues
```bash
# Install cargo-cross for easier cross-compilation
cargo install cross

# Check available Rust targets
rustc --print target-list
```

### 8.2 GitHub CLI Issues
```bash
# Re-authenticate if needed
gh auth logout
gh auth login
```

### 8.3 PyPI Publishing Issues
```bash
# Check uv installation
which uv
uv --version

# Manual PyPI upload (alternative)
pip install twine
twine upload dist/*
```

### 8.4 README.md Git Diff
The build scripts modify `README.md` for PyPI compatibility. This is normal and the changes are temporary during build.

## 9. Tips

1. **Test locally first**: Build and test on your platform before releasing
2. **Use dry runs**: Test GitHub release creation with a test tag first
3. **Check cross-compilation**: Test cross-compiled binaries on target platforms
4. **Pre-releases**: Use pre-release versions for testing before stable releases
5. **Clean workspace**: Ensure working directory is clean before releasing