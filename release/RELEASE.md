# Release Instructions

This document explains how to create a new release of Muff and publish it to GitHub and PyPI.

## 1. Overview

The release process consists of these steps:
1. **Build** - Create wheels and binaries for target platforms
2. **GitHub Release** - Create a GitHub release with artifacts
3. **PyPI Publish** - Upload wheels to PyPI

## 2. Prerequisites

### 2.1 Automatic Prerequisites (Linux Script)
The Linux build script (`step-1-build-linux.sh`) automatically handles prerequisites:
- **build-essential** (gcc, make, etc.)
- **curl** (for Rust installation)
- **python3, python3-pip, python3-venv**
- **rustc/cargo** (installed via rustup if missing)

All prerequisites are installed with user consent via interactive prompts. **Note**: Cross-compilation removed due to reliability issues - run on native architecture instead.

### 2.2 Automatic Prerequisites (Windows Script)
The Windows build script (`step-1-build-windows.sh`) handles prerequisites automatically for different Windows environments:

**WSL (Windows Subsystem for Linux):**
- **python3, python3-pip, python3-venv, build-essential** (via apt)
- **rustc/cargo** (installed via curl + rustup)

**Native Windows (Git Bash/MSYS2):**
- **Python 3** (provides installation guidance)
- **Rust/Cargo** (provides installation links)
- **Visual Studio Build Tools** (optional, enables MSVC target)

**Supported Windows Environments:**
- **WSL/WSL2** (Windows Subsystem for Linux) - Recommended
- **Git Bash** (bundled with Git for Windows)
- **MSYS2** (Unix-like environment)

### 2.3 Manual Prerequisites (macOS Scripts)
For macOS scripts, ensure you have:
- **Python 3** with `pip`
- **Rust/Cargo** (install via [rustup.rs](https://rustup.rs/))
- **GitHub CLI** (`brew install gh`) for releases
- **uv** (auto-installed by scripts) for PyPI publishing

### 2.4 Windows Setup Instructions

#### 2.4.1 Option 1: WSL (Recommended)
```powershell
# Install WSL2 with Ubuntu
wsl --install

# Or install Ubuntu specifically
wsl --install -d Ubuntu

# After setup, run the script in WSL
wsl
cd /mnt/c/path/to/your/project
./release/step-1-build-windows.sh
```

#### 2.4.2 Option 2: Git Bash
```bash
# Install Git for Windows (includes Git Bash)
# Download from: https://git-scm.com/download/win

# Install Python
winget install Python.Python.3

# Install Rust
winget install Rustlang.Rustup

# Run the script in Git Bash
./release/step-1-build-windows.sh
```

#### 2.4.3 Option 3: Visual Studio Build Tools (For MSVC Target)
```powershell
# Install Visual Studio Build Tools
winget install Microsoft.VisualStudio.2022.BuildTools

# Or download from: https://visualstudio.microsoft.com/downloads/
# This enables the x86_64-pc-windows-msvc target for better compatibility
```

### 2.5 Optional Cross-compilation Tools
For building Linux and Windows binaries from macOS:
```bash
# Option 1: Use cargo-cross (recommended)
cargo install cross

# Option 2: Install cross-compilation toolchains
brew install messense/macos-cross-toolchains/x86_64-unknown-linux-gnu
brew install messense/macos-cross-toolchains/aarch64-unknown-linux-gnu
brew install mingw-w64  # for Windows
```

### 2.6 Authentication Setup
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
Builds natively on Linux (with automatic prerequisite installation):
```bash
# On x86_64 Linux machine
./release/step-1-build-linux.sh  # Builds x86_64 only

# On ARM64 Linux machine  
./release/step-1-build-linux.sh  # Builds ARM64 only
```
**Requirements:** Linux machine (EC2, VPS, local Linux, etc.)
**Outputs:**
- `dist/*.whl` - Python wheels for current architecture
- `muff-{arch}-unknown-linux-gnu.tar.gz` - Linux binary for current architecture

#### 3.2.3 `step-1-build-windows.sh`
Builds natively on Windows (supports WSL, Git Bash, MSYS2):
```bash
./release/step-1-build-windows.sh
```
**Requirements:** Windows machine with WSL/Git Bash/MSYS2
**Outputs:**
- `dist/*.whl` - Python wheels
- `muff-x86_64-pc-windows-msvc.zip` - Windows x64 binary (MSVC)
- `muff-x86_64-pc-windows-gnu.zip` - Windows x64 binary (GNU)

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

### 4.2 Method 2: Native Builds on Multiple Platforms (Recommended for Production)
For production releases, build natively on each platform for best compatibility:

**On macOS (builds both Intel and Apple Silicon):**
```bash
./release/step-1-build-macos.sh
```

**On x86_64 Linux machine:**
```bash
./release/step-1-build-linux.sh  # Builds x86_64 Linux
```

**On ARM64 Linux machine:**
```bash
./release/step-1-build-linux.sh  # Builds ARM64 Linux
```

**On Windows (WSL/Git Bash):**
```bash
./release/step-1-build-windows.sh
```

**Combine and release:**
```bash
# Collect all artifacts from different machines
# Then create release and publish
./release/step-2-create-release.sh v1.0.0
./release/step-3-publish-pypi.sh
```

### 4.3 Method 3: Single Platform Step-by-Step
```bash
# 1. Build for your platform
./release/step-1-build-macos.sh

# 2. Create GitHub release
./release/step-2-create-release.sh v1.0.0

# 3. Publish to PyPI
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

### 8.4 Windows-Specific Issues

#### 8.4.1 WSL Environment
```bash
# If script doesn't detect WSL properly
cat /proc/version  # Should show Microsoft

# Update WSL if needed
wsl --update

# Fix permission issues
chmod +x release/step-1-build-windows.sh
```

#### 8.4.2 MSVC Target Issues
```powershell
# Install Visual Studio Build Tools
winget install Microsoft.VisualStudio.2022.BuildTools

# Verify installation
where cl.exe

# Add to PATH if needed (in CMD/PowerShell)
set PATH=%PATH%;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.XX.XXXXX\bin\Hostx64\x64
```

#### 8.4.3 Git Bash Path Issues
```bash
# If Python not found in Git Bash
which python
which python3

# Add Python to PATH in Git Bash
export PATH="/c/Users/$USERNAME/AppData/Local/Programs/Python/Python311:$PATH"
```

### 8.5 README.md Git Diff
The build scripts modify `README.md` for PyPI compatibility. This is normal and the changes are temporary during build.

## 9. Tips

1. **Test locally first**: Build and test on your platform before releasing
2. **Use native builds**: For production releases, build natively on each platform (macOS, Linux, Windows) for best compatibility
3. **WSL for Windows**: Use WSL on Windows for the most reliable build experience
4. **Visual Studio Build Tools**: Install on Windows for MSVC target support 
5. **Use dry runs**: Test GitHub release creation with a test tag first
6. **Pre-releases**: Use pre-release versions for testing before stable releases
7. **Clean workspace**: Ensure working directory is clean before releasing
8. **Prerequisites handled**: Linux and Windows scripts handle most prerequisites automatically
9. **Virtual environments**: All scripts use isolated virtual environments for Python dependencies