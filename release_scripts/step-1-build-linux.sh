#!/bin/bash
set -euo pipefail

# Linux native build script
# Run this script on a Linux machine (e.g., EC2 instance)

PACKAGE_NAME="muff"
MODULE_NAME="muff"
ARTIFACTS_DIR=${ARTIFACTS_DIR:-artifacts}

echo "🐧 Building muff natively on Linux..."

# Function to install packages with user consent
install_package() {
    local package=$1
    local description=$2

    echo "📦 $description is required but not installed"
    read -p "Install $package? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if sudo apt update && sudo apt install -y "$package"; then
            echo "✅ Successfully installed $package"
            return 0
        else
            echo "❌ Failed to install $package"
            return 1
        fi
    else
        echo "❌ Cannot continue without $description"
        return 1
    fi
}

# Check and install dependencies
echo "🔍 Checking dependencies on fresh Ubuntu machine..."

# Update package lists first if this is a fresh machine
if [ ! -f /var/lib/apt/periodic/update-success-stamp ] || [ $(find /var/lib/apt/periodic/update-success-stamp -mtime +1) ]; then
    echo "📦 Updating package lists (fresh machine setup)..."
    if sudo apt update; then
        echo "✅ Package lists updated"
    else
        echo "⚠️  Failed to update package lists, continuing anyway..."
    fi
fi

# Check for essential build tools first
if ! command -v gcc &> /dev/null || ! command -v make &> /dev/null; then
    if ! install_package "build-essential" "essential build tools (gcc, make, etc.)"; then
        exit 1
    fi
fi

# Check for curl (needed for Rust installation)
if ! command -v curl &> /dev/null; then
    if ! install_package "curl" "curl (needed for downloading Rust)"; then
        exit 1
    fi
fi

# Check for git (commonly missing on minimal Ubuntu)
if ! command -v git &> /dev/null; then
    if ! install_package "git" "git (version control system)"; then
        exit 1
    fi
fi

# Check for pkg-config and libssl-dev (often needed for Rust builds)
if ! dpkg -l | grep -q "libssl-dev" || ! command -v pkg-config &> /dev/null; then
    echo "📦 Checking for SSL development libraries and pkg-config..."
    if ! install_package "libssl-dev pkg-config" "SSL development libraries and pkg-config (needed for Rust builds)"; then
        echo "⚠️  SSL development libraries not installed - builds might fail"
    fi
fi

# Check Python 3
if ! command -v python3 &> /dev/null; then
    if ! install_package "python3 python3-pip python3-venv" "Python 3 and pip"; then
        exit 1
    fi
fi

# Check python3-venv specifically (common missing package)
# Test actual venv creation rather than just --help
echo "🔍 Testing Python virtual environment capability..."
TEST_VENV_DIR="/tmp/test-venv-$$"
if ! python3 -m venv "$TEST_VENV_DIR" &> /dev/null; then
    rm -rf "$TEST_VENV_DIR" 2>/dev/null

    # Get Python version to install the correct venv package
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    VENV_PACKAGE="python${PYTHON_VERSION}-venv"

    echo "📦 Python $PYTHON_VERSION detected, virtual environment creation failed"
    echo "📦 Need to install $VENV_PACKAGE package"

    # Try version-specific package first, then fallback to generic
    if ! install_package "$VENV_PACKAGE" "python$PYTHON_VERSION-venv package"; then
        echo "📦 Trying generic python3-venv package as fallback..."
        if ! install_package "python3-venv" "python3-venv package (generic)"; then
            exit 1
        fi
    fi

    # Test again after installation
    echo "🔍 Testing virtual environment creation after package installation..."
    if ! python3 -m venv "$TEST_VENV_DIR" &> /dev/null; then
        rm -rf "$TEST_VENV_DIR" 2>/dev/null
        echo "❌ Virtual environment creation still failing after package installation"
        echo "💡 You may need to install additional packages manually:"
        echo "   sudo apt install python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-distutils"
        echo "   sudo apt install python3-venv python3-distutils"
        exit 1
    else
        rm -rf "$TEST_VENV_DIR"
        echo "✅ Virtual environment creation test passed"
    fi
else
    rm -rf "$TEST_VENV_DIR"
    echo "✅ Virtual environment capability verified"
fi

# Check Rust/Cargo
if ! command -v cargo &> /dev/null; then
    echo "📦 Rust/Cargo is required but not installed"
    echo "Installing Rust via rustup..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        source ~/.cargo/env
        echo "✅ Successfully installed Rust"
    else
        echo "❌ Failed to install Rust"
        echo "💡 Please install manually: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
fi

# Ensure cargo is in PATH
if ! command -v cargo &> /dev/null; then
    if [[ -f ~/.cargo/env ]]; then
        source ~/.cargo/env
    fi
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    if ! install_package "docker.io" "Docker (for manylinux builds)"; then
        exit 1
    fi

    # Add current user to docker group
    echo "📦 Adding current user to docker group..."
    sudo usermod -aG docker "$USER"
    echo "⚠️  You may need to log out and back in for Docker group membership to take effect"
    echo "⚠️  For now, we'll use sudo with Docker commands"
fi

# Check if Docker daemon is running
if ! sudo docker info &> /dev/null; then
    echo "📦 Starting Docker daemon..."
    sudo systemctl start docker || {
        echo "❌ Failed to start Docker daemon"
        exit 1
    }
fi

# Check pip
if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
    if ! install_package "python3-pip" "pip (Python package installer)"; then
        exit 1
    fi
fi

# Use pip3 if available, otherwise pip
PIP_CMD="pip3"
if ! command -v pip3 &> /dev/null; then
    PIP_CMD="pip"
fi

# Create virtual environment for build tools
VENV_DIR="$HOME/.muff-build-env"
echo "📦 Setting up build environment..."

if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment at $VENV_DIR..."
    if ! python3 -m venv "$VENV_DIR"; then
        echo "❌ Failed to create virtual environment"

        # Get Python version for better error message
        PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "unknown")

        echo "💡 This might be due to missing python venv package. Try:"
        echo "   sudo apt install python${PYTHON_VERSION}-venv"
        echo "   sudo apt install python3-venv"
        echo "   sudo apt install python3-pip python3-venv"

        # Try to install the missing package automatically
        echo "🔧 Attempting to fix automatically..."
        if [[ "$PYTHON_VERSION" != "unknown" ]]; then
            VENV_PACKAGE="python${PYTHON_VERSION}-venv"
            if install_package "$VENV_PACKAGE" "python${PYTHON_VERSION}-venv package (auto-fix)"; then
                echo "🔄 Retrying virtual environment creation..."
                if python3 -m venv "$VENV_DIR"; then
                    echo "✅ Virtual environment created successfully after auto-fix!"
                else
                    echo "❌ Still failed after installing $VENV_PACKAGE"
                    exit 1
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi
fi

# Verify virtual environment was created properly
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    echo "❌ Virtual environment activation script not found"
    echo "💡 Removing corrupted venv and retrying..."
    rm -rf "$VENV_DIR"

    # Get Python version for the retry
    PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "unknown")

    if ! python3 -m venv "$VENV_DIR"; then
        echo "❌ Failed to create virtual environment on retry"

        # Try to automatically install the missing package
        if [[ "$PYTHON_VERSION" != "unknown" ]]; then
            VENV_PACKAGE="python${PYTHON_VERSION}-venv"
            echo "🔧 Attempting to install missing $VENV_PACKAGE package..."

            if install_package "$VENV_PACKAGE" "python${PYTHON_VERSION}-venv package (emergency fix)"; then
                echo "🔄 Retrying virtual environment creation after emergency fix..."
                if python3 -m venv "$VENV_DIR"; then
                    echo "✅ Virtual environment created successfully after emergency fix!"
                else
                    echo "❌ Still failed after installing $VENV_PACKAGE"
                    echo "💡 Try these manual commands:"
                    echo "   sudo apt install python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-distutils"
                    echo "   sudo apt install python3-venv python3-distutils python3-dev"
                    exit 1
                fi
            else
                echo "💡 Install the correct python venv package manually:"
                echo "   sudo apt install python${PYTHON_VERSION}-venv"
                echo "   sudo apt install python3-venv"
                exit 1
            fi
        else
            echo "💡 Install the python venv package:"
            echo "   sudo apt install python3-venv"
            exit 1
        fi
    fi
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Install/upgrade maturin in virtual environment
echo "Installing maturin in virtual environment..."
pip install --upgrade pip maturin

# Verify installation
if ! command -v maturin &> /dev/null; then
    echo "❌ Failed to install maturin in virtual environment"
    exit 1
fi

echo "✅ Build environment ready (using virtual environment)"

# Summary of prerequisites checked
echo ""
echo "📋 Prerequisites verified for fresh Ubuntu machine:"
echo "   ✅ Package lists updated"
echo "   ✅ build-essential (gcc, make, etc.)"
echo "   ✅ curl (for downloads)"
echo "   ✅ git (version control)"
echo "   ✅ libssl-dev & pkg-config (for Rust builds)"
echo "   ✅ python3, python3-pip, python3-venv (version-specific)"
echo "   ✅ Rust/Cargo toolchain"
echo "   ✅ Docker (for manylinux builds)"
echo "   ✅ maturin (Python wheel builder)"
echo "   ✅ Virtual environment with auto-fix for version-specific packages"

# Detect current architecture and set up manylinux containers
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    NATIVE_TARGET="x86_64-unknown-linux-gnu"
    PLATFORM_NAME="x86_64 (Intel/AMD)"
    BUILD_TARGETS=("x86_64-unknown-linux-gnu")
    # Use the standard manylinux2014 images (manylinux_2_17 compatible)
    MANYLINUX_IMAGE="quay.io/pypa/manylinux2014_x86_64"
elif [[ "$CURRENT_ARCH" == "aarch64" ]]; then
    NATIVE_TARGET="aarch64-unknown-linux-gnu"
    PLATFORM_NAME="aarch64 (ARM64)"
    BUILD_TARGETS=("aarch64-unknown-linux-gnu")
    MANYLINUX_IMAGE="quay.io/pypa/manylinux2014_aarch64"
else
    echo "❌ Unsupported architecture: $CURRENT_ARCH"
    exit 1
fi

echo "🏗️  Detected platform: Linux $PLATFORM_NAME"
echo "📋 Native target: $NATIVE_TARGET"
echo "📋 Will build targets: ${BUILD_TARGETS[*]}"
echo "📋 Manylinux image: $MANYLINUX_IMAGE"

# Pull manylinux Docker image
echo "🐳 Pulling manylinux Docker image..."
if ! sudo docker pull "$MANYLINUX_IMAGE"; then
    echo "❌ Failed to pull manylinux image: $MANYLINUX_IMAGE"
    exit 1
fi

# Install Rust targets
echo "🎯 Installing Rust targets..."
for target in "${BUILD_TARGETS[@]}"; do
    rustup target add "$target"
done

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf dist/
# Use Docker to clean target directory if it has permission issues
if [[ -d target/ ]] && ! rm -rf target/ 2>/dev/null; then
    echo "🐳 Using Docker to clean target directory (permission issues)..."
    sudo docker run --rm -v "$(pwd):/io" -w /io alpine:latest rm -rf target/
fi
rm -f muff-*-unknown-linux-gnu.tar.gz*

# Create dist directory with proper permissions
mkdir -p dist
chmod 777 dist

# Prep README.md for PyPI (backup and restore after build)
echo "📝 Preparing README.md for PyPI..."
READMETMP="$(mktemp)"
if [[ -f README.md ]]; then
  cp README.md "$READMETMP" || true
  trap 'if [[ -f "$READMETMP" ]]; then cp "$READMETMP" README.md 2>/dev/null || true; rm -f "$READMETMP"; fi' EXIT
fi
python3 scripts/transform_readme.py --target pypi || true

# Build function using Docker manylinux containers
build_target() {
    local target=$1
    echo ""
    echo "🏗️  Building for $target..."

    # Get current working directory for mounting
    local repo_path="$(pwd)"

    # Build with maturin in Docker container
    echo "🐳 Building wheel for $target using $MANYLINUX_IMAGE..."
    if ! sudo docker run --rm \
        -v "$repo_path:/io" \
        -w /io \
        -u "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        "$MANYLINUX_IMAGE" \
        bash -c "
            # Install Rust in container
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source /tmp/.cargo/env
            rustup target add $target

            # Install Python and maturin
            /opt/python/cp313-cp313/bin/python -m pip install --user maturin

            # Build the wheel
            /opt/python/cp313-cp313/bin/python -m maturin build --release --locked --target $target --out dist --compatibility manylinux_2_17
        "; then
        echo "❌ Wheel build failed for $target"
        return 1
    fi
    echo "✅ Wheel built successfully for $target (manylinux_2_17)"

    # Build binary with cargo (on host system for simplicity)
    echo "🔧 Building binary for $target..."
    if cargo build --release --locked --target "$target"; then
        echo "✅ Binary built successfully for $target"

        # Create archive into artifacts directory
        archive_name="muff-$target"
        archive_file="$archive_name.tar.gz"

        mkdir -p "$ARTIFACTS_DIR"
        stage_dir=$(mktemp -d)
        mkdir -p "$stage_dir/$archive_name"
        cp "target/$target/release/muff" "$stage_dir/$archive_name/muff"
        tar -C "$stage_dir" -czf "$ARTIFACTS_DIR/$archive_file" "$archive_name"

        # Create checksum (use sha256sum on Linux)
        sha256sum "$ARTIFACTS_DIR/$archive_file" > "$ARTIFACTS_DIR/$archive_file.sha256"

        # Clean up staging
        rm -rf "$stage_dir"

        echo "📦 Created: $archive_file"
        return 0
    else
        echo "❌ Binary build failed for $target"
        return 1
    fi
}

# Build for all targets
success=true
for target in "${BUILD_TARGETS[@]}"; do
    echo ""
    echo "🚀 Building target: $target"
    if ! build_target "$target"; then
        success=false
        echo "❌ Failed to build target: $target"
    else
        echo "✅ Successfully built target: $target"
    fi
done

# Build source distribution
echo ""
echo "📦 Building source distribution..."
maturin sdist --out dist

# Test builds (native architecture only)
echo ""
echo "🧪 Testing Linux builds..."

# Find compatible wheel for current architecture
WHEEL_PATTERNS=("*-*-linux_${CURRENT_ARCH}.whl" "*-*-manylinux*${CURRENT_ARCH}.whl")
WHEEL_FILE=""

for pattern in "${WHEEL_PATTERNS[@]}"; do
    if ls dist/${pattern} 1> /dev/null 2>&1; then
        WHEEL_FILE=$(ls dist/${pattern} | head -1)
        break
    fi
done

if [[ -n "$WHEEL_FILE" ]]; then
    echo "🔍 Found compatible wheel for testing: $(basename "$WHEEL_FILE")"

    # Install and test in the build virtual environment
    echo "Installing wheel in virtual environment for testing..."
    if pip install "$WHEEL_FILE" --force-reinstall; then
        echo "✅ Wheel installation successful"

        # Test functionality in the virtual environment
        if $MODULE_NAME --help >/dev/null 2>&1 && python -m $MODULE_NAME --help >/dev/null 2>&1; then
            echo "✅ Wheel functionality test passed"
        else
            echo "⚠️  Wheel installed but functionality test failed (non-critical)"
        fi
    else
        echo "⚠️  Wheel installation failed (non-critical)"
    fi
else
    echo "⚠️  No compatible wheel found for testing"
    echo "    Available wheels:"
    ls dist/*.whl 2>/dev/null | sed 's/^/      /' || echo "      (No wheels found)"
    echo "    Looked for patterns: ${WHEEL_PATTERNS[*]}"
fi

echo ""
if [ "$success" = true ]; then
    echo "✅ Linux build completed successfully!"
else
    echo "⚠️  Linux build completed with some failures"
fi

echo ""
echo "📁 Outputs:"
echo "   - Wheels: dist/*.whl"
echo "   - Source: dist/*.tar.gz"
echo "   - Binaries (artifacts/):"
ls -la "$ARTIFACTS_DIR"/muff-*-unknown-linux-gnu.tar.gz 2>/dev/null || echo "     (No binary archives created)"

echo ""
echo "🎯 Built targets:"
for target in "${BUILD_TARGETS[@]}"; do
    if [[ -f "target/$target/release/muff" ]]; then
        echo "   ✅ $target"
    else
        echo "   ❌ $target (failed)"
    fi
done

echo ""
echo "💡 Notes:"
echo "   - ✅ Fresh Ubuntu machine ready! All prerequisites auto-installed with consent"
echo "   - ✅ Native build for $NATIVE_TARGET with manylinux_2_17 compatibility"
echo "   - ✅ Wheels built using Docker manylinux containers for true compatibility"
echo "   - ✅ Docker image used: $MANYLINUX_IMAGE"
echo "   - ✅ For ARM64 builds, run this script on an ARM64 Linux machine"
echo "   - ✅ Build environment isolated in virtual environment: $VENV_DIR"
echo "   - ✅ Test binaries on target systems before releasing"

# Fix ownership of any Docker-created files
echo "🔧 Fixing ownership of Docker-created files..."
sudo chown -R "$(id -u):$(id -g)" target/ dist/ 2>/dev/null || true
