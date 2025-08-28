# Release Instructions

Instructions for creating releases of Muff and publishing to GitHub and PyPI.

## 1. Prerequisites

### 1.1 macOS (Auto-installed)
The macOS script automatically installs:
- Homebrew (if not present)
- Python 3 with pip
- Rust/Cargo (via rustup)
- GitHub CLI (`brew install gh` - for releases only)
- uv (auto-installed by scripts)

### 1.2 Linux (Auto-installed)
The Linux script automatically installs:
- build-essential, curl, git, libssl-dev, pkg-config
- python3, python3-pip, python3-venv
- rustc/cargo (via rustup)

### 1.3 Windows (Multiple options)

#### 1.3.1 WSL (Recommended)
- Install: `wsl --install -d Ubuntu`
- Prerequisites auto-installed like Linux

#### 1.3.2 Git Bash
- Install Git for Windows
- Install Python: `winget install Python.Python.3`
- Install Rust: `winget install Rustlang.Rustup`

### 1.4 Authentication
```bash
gh auth login  # For GitHub releases
export PYPI_API_TOKEN=your-token  # For PyPI (or use trusted publishing)
```

## 2. Build Scripts

### 2.1 Individual Platform Builds

#### 2.1.1 macOS
```bash
./release/step-1-build-macos.sh
```
Builds for both Intel and Apple Silicon.

#### 2.1.2 Linux
```bash
./release/step-1-build-linux.sh
```
Run on native Linux machine (x86_64 or ARM64).
- Builds manylinux_2_17 compatible wheels for better GitLab CI/CD compatibility
- x86_64 builds produce `manylinux_2_17_x86_64` wheels instead of `manylinux_2_39_x86_64`

#### 2.1.3 Windows
```bash
./release/step-1-build-windows.sh
```
Run on Windows with WSL, Git Bash, or MSYS2.

### 2.2 Release Scripts

#### 2.2.1 Create GitHub Release
```bash
./release/step-2-create-release.sh v1.0.0
```

#### 2.2.2 Publish to PyPI
```bash
./release/step-3-publish-pypi.sh
```

## 3. Release Workflow

### 3.1 Single Platform Release
```bash
# 1. Build
./release/step-1-build-macos.sh

# 2. Create GitHub release
./release/step-2-create-release.sh v1.0.0

# 3. Publish to PyPI
./release/step-3-publish-pypi.sh
```

### 3.2 Multi-Platform Release
Build on each platform, then combine artifacts:

```bash
# On macOS
./release/step-1-build-macos.sh

# On Linux
./release/step-1-build-linux.sh

# On Windows
./release/step-1-build-windows.sh

# Combine artifacts and release
./release/step-2-create-release.sh v1.0.0
./release/step-3-publish-pypi.sh
```

## 4. Version Format

Use semantic versioning with `v` prefix:
- `v1.0.0` - Stable release
- `v1.0.0-beta.1` - Pre-release

## 5. Outputs

- **GitHub**: Binaries, wheels, checksums at `/releases/tag/v1.0.0`
- **PyPI**: Wheels at https://pypi.org/project/muff/
- **Local**: `dist/*.whl`, binary archives with checksums

## 6. Troubleshooting

### 6.1 GitHub CLI
```bash
gh auth logout && gh auth login
```

### 6.2 PyPI Authentication
Set `PYPI_API_TOKEN` environment variable or use trusted publishing from GitHub Actions.

### 6.3 Platform Issues
- **Linux**: Scripts handle missing dependencies automatically
- **Windows**: Use WSL for best compatibility
- **macOS**: Scripts handle missing dependencies automatically

### 6.4 GitLab CI/CD Issues
If GitLab runners build from source instead of using pre-built wheels:
- Ensure you're building with `manylinux_2_17` compatibility (automatically handled by updated script)
- x86_64 builds now produce `manylinux_2_17_x86_64.whl` instead of `manylinux_2_39_x86_64.whl`
- GitLab runners use standard x86_64 architecture and expect broader compatibility
- Re-run `./release/step-1-build-linux.sh` on x86_64 Ubuntu to generate compatible wheels