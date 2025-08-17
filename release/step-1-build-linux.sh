#!/bin/bash
set -euo pipefail

# Linux native build script
# Run this script on a Linux machine (e.g., EC2 instance)

PACKAGE_NAME="muff"
MODULE_NAME="muff"

echo "🐧 Building muff natively on Linux..."

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    echo "💡 Install with: sudo apt update && sudo apt install python3 python3-pip"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo "❌ Rust/Cargo is required but not installed"
    echo "💡 Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
    echo "❌ pip is required but not installed"
    echo "💡 Install with: sudo apt install python3-pip"
    exit 1
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
        echo "💡 Make sure python3-venv is installed: sudo apt install python3-venv"
        exit 1
    fi
fi

# Verify virtual environment was created properly
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    echo "❌ Virtual environment activation script not found"
    echo "💡 Removing corrupted venv and retrying..."
    rm -rf "$VENV_DIR"
    if ! python3 -m venv "$VENV_DIR"; then
        echo "❌ Failed to create virtual environment on retry"
        echo "💡 Make sure python3-venv is installed: sudo apt install python3-venv"
        exit 1
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

# Detect current architecture
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    NATIVE_TARGET="x86_64-unknown-linux-gnu"
    CROSS_TARGET="aarch64-unknown-linux-gnu"
    PLATFORM_NAME="x86_64 (Intel/AMD)"
elif [[ "$CURRENT_ARCH" == "aarch64" ]]; then
    NATIVE_TARGET="aarch64-unknown-linux-gnu"
    CROSS_TARGET="x86_64-unknown-linux-gnu"
    PLATFORM_NAME="aarch64 (ARM64)"
else
    echo "❌ Unsupported architecture: $CURRENT_ARCH"
    exit 1
fi

echo "🏗️  Detected platform: Linux $PLATFORM_NAME"
echo "📋 Native target: $NATIVE_TARGET"
echo "📋 Cross-compile target: $CROSS_TARGET"

# Install Rust targets
echo "🎯 Installing Rust targets..."
rustup target add "$NATIVE_TARGET"
rustup target add "$CROSS_TARGET"

# Check for cross-compilation tools for the other architecture
if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    CROSS_COMPILER="aarch64-linux-gnu-gcc"
elif [[ "$CURRENT_ARCH" == "aarch64" ]]; then
    CROSS_COMPILER="x86_64-linux-gnu-gcc"
fi

CROSS_AVAILABLE=false
if command -v "$CROSS_COMPILER" &> /dev/null; then
    echo "✅ Found cross-compiler: $CROSS_COMPILER"
    CROSS_AVAILABLE=true
else
    echo "⚠️  Cross-compiler not found: $CROSS_COMPILER"
    echo "💡 To enable cross-compilation, install:"
    if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
        echo "    sudo apt install gcc-aarch64-linux-gnu"
    else
        echo "    sudo apt install gcc-x86-64-linux-gnu"
    fi
    echo "    (Cross-compilation will be skipped)"
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf dist/
rm -rf target/*/release/
rm -f muff-*-unknown-linux-gnu.tar.gz*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
python3 release/transform_readme_temp.py --action create

# Define targets to build
TARGETS=("$NATIVE_TARGET")
if [[ "$CROSS_AVAILABLE" == "true" ]]; then
    TARGETS+=("$CROSS_TARGET")
fi

# Build function for each target
build_target() {
    local target=$1
    local is_native=$2
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
    
    # Set cross-compilation environment if needed
    if [[ "$is_native" == "false" ]]; then
        if [[ "$target" == "aarch64-unknown-linux-gnu" ]]; then
            export CC="aarch64-linux-gnu-gcc"
            export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
        elif [[ "$target" == "x86_64-unknown-linux-gnu" ]]; then
            export CC="x86_64-linux-gnu-gcc"
            export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"
        fi
    fi
    
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

# Build for all targets
success=true
for target in "${TARGETS[@]}"; do
    if [[ "$target" == "$NATIVE_TARGET" ]]; then
        if ! build_target "$target" "true"; then
            success=false
        fi
    else
        if ! build_target "$target" "false"; then
            echo "⚠️  Cross-compilation failed for $target (continuing...)"
        fi
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
for target in "${TARGETS[@]}"; do
    if [[ -f "target/$target/release/muff" ]]; then
        echo "   ✅ $target"
    else
        echo "   ❌ $target (failed)"
    fi
done

echo ""
echo "💡 Notes:"
echo "   - Native build for $NATIVE_TARGET should always work"
if [[ "$CROSS_AVAILABLE" == "true" ]]; then
    echo "   - Cross-compilation for $CROSS_TARGET attempted"
else
    echo "   - Cross-compilation skipped (install cross-compiler if needed)"
fi
echo "   - Test binaries on target systems before releasing"

# Clean up temporary files
echo ""
echo "🔄 Cleaning up temporary files..."
python3 release/transform_readme_temp.py --action cleanup