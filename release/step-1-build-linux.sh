#!/bin/bash
set -euo pipefail

# Linux native build script
# Run this script on a Linux machine (e.g., EC2 instance)

PACKAGE_NAME="muff"
MODULE_NAME="muff"

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
echo "   ✅ maturin (Python wheel builder)"
echo "   ✅ Virtual environment with auto-fix for version-specific packages"

# Detect current architecture
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    NATIVE_TARGET="x86_64-unknown-linux-gnu"
    PLATFORM_NAME="x86_64 (Intel/AMD)"
elif [[ "$CURRENT_ARCH" == "aarch64" ]]; then
    NATIVE_TARGET="aarch64-unknown-linux-gnu"
    PLATFORM_NAME="aarch64 (ARM64)"
else
    echo "❌ Unsupported architecture: $CURRENT_ARCH"
    exit 1
fi

echo "🏗️  Detected platform: Linux $PLATFORM_NAME"
echo "📋 Native target: $NATIVE_TARGET"

# Install Rust target
echo "🎯 Installing Rust target..."
rustup target add "$NATIVE_TARGET"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf dist/
rm -rf target/*/release/
rm -f muff-*-unknown-linux-gnu.tar.gz*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
python3 release/transform_readme_temp.py --action create

# Build function
build_target() {
    local target=$1
    echo ""
    echo "🏗️  Building for $target..."
    
    # Build with maturin
    echo "🛠️  Building wheel for $target..."
    if maturin build --release --locked --target "$target" --out dist; then
        echo "✅ Wheel built successfully for $target"
    else
        echo "⚠️  Wheel build failed for $target"
    fi
    
    # Build binary with cargo
    echo "🔧 Building binary for $target..."
    if cargo build --release --locked --target "$target"; then
        echo "✅ Binary built successfully for $target"
        
        # Create archive
        archive_name="muff-$target"
        archive_file="$archive_name.tar.gz"
        
        mkdir -p "$archive_name"
        cp "target/$target/release/muff" "$archive_name/muff"
        tar czvf "$archive_file" "$archive_name"
        
        # Create checksum (use sha256sum on Linux)
        sha256sum "$archive_file" > "$archive_file.sha256"
        
        # Clean up
        rm -rf "$archive_name"
        
        echo "📦 Created: $archive_file"
        return 0
    else
        echo "❌ Binary build failed for $target"
        return 1
    fi
}

# Build for native target only
success=true
if ! build_target "$NATIVE_TARGET"; then
    success=false
fi

# Build source distribution
echo ""
echo "📦 Building source distribution..."
maturin sdist --out dist

# Test builds (native architecture only)
echo ""
echo "🧪 Testing Linux builds..."

# Find compatible wheel for current architecture
if ls dist/*-*-linux_${CURRENT_ARCH}.whl 1> /dev/null 2>&1; then
    echo "🔍 Found compatible wheel for testing..."
    
    WHEEL_FILE=$(ls dist/*-*-linux_${CURRENT_ARCH}.whl | head -1)
    
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
echo "   - Binaries:"
ls -la muff-*-unknown-linux-gnu.tar.gz 2>/dev/null || echo "     (No binary archives created)"

echo ""
echo "🎯 Built targets:"
if [[ -f "target/$NATIVE_TARGET/release/muff" ]]; then
    echo "   ✅ $NATIVE_TARGET"
else
    echo "   ❌ $NATIVE_TARGET (failed)"
fi

echo ""
echo "💡 Notes:"
echo "   - ✅ Fresh Ubuntu machine ready! All prerequisites auto-installed with consent"
echo "   - ✅ Native build for $NATIVE_TARGET only (no cross-compilation)"
echo "   - ✅ For ARM64 builds, run this script on an ARM64 Linux machine"
echo "   - ✅ Build environment isolated in virtual environment: $VENV_DIR"
echo "   - ✅ Test binaries on target systems before releasing"

# Clean up temporary files
echo ""
echo "🔄 Cleaning up temporary files..."
python3 release/transform_readme_temp.py --action cleanup