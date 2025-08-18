#!/bin/bash
set -euo pipefail

# macOS build script - builds for both Intel and Apple Silicon

PACKAGE_NAME="muff"
MODULE_NAME="muff"

echo "🍎 Building muff for macOS..."

# Check and install prerequisites
echo "🔍 Checking prerequisites..."

# Check Homebrew
if ! command -v brew &> /dev/null; then
    echo "⚠️  Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for current session
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        export PATH="/opt/homebrew/bin:$PATH"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        export PATH="/usr/local/bin:$PATH"
    fi
fi

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo "⚠️  Python 3 not found. Installing via Homebrew..."
    brew install python
fi

# Check pip
if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
    echo "⚠️  pip not found. Installing via Python..."
    python3 -m ensurepip --upgrade
fi

# Use pip3 if pip is not available
PIP_CMD="pip"
if ! command -v pip &> /dev/null && command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
fi

# Check Rust/Cargo
if ! command -v cargo &> /dev/null; then
    echo "⚠️  Rust/Cargo not found. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
fi

echo "✅ Prerequisites check complete"

# Install maturin if not available
if ! command -v maturin &> /dev/null; then
    echo "📦 Installing maturin..."
    $PIP_CMD install maturin
fi

# Install macOS targets
echo "🎯 Installing Rust targets for macOS..."
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin

# Clean previous builds
echo "🧹 Cleaning previous macOS builds..."
rm -rf dist/
rm -rf target/aarch64-apple-darwin/release/
rm -rf target/x86_64-apple-darwin/release/
rm -f muff-*-apple-darwin.tar.gz*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
python release/transform_readme_temp.py --action create

# Define macOS targets
declare -a TARGETS=(
    "aarch64-apple-darwin"
    "x86_64-apple-darwin"
)

# Build function for each target
build_target() {
    local target=$1
    echo ""
    echo "🏗️  Building for $target..."
    
    # Build with maturin
    echo "🛠️  Building wheel for $target..."
    if maturin build --release --locked --target "$target" --out dist; then
        echo "✅ Wheel built successfully for $target"
    else
        echo "❌ Wheel build failed for $target"
        return 1
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
        
        # Create checksum
        shasum -a 256 "$archive_file" > "$archive_file.sha256"
        
        # Clean up
        rm -rf "$archive_name"
        
        echo "📦 Created: $archive_file"
    else
        echo "❌ Binary build failed for $target"
        return 1
    fi
}

# Build for all macOS targets
success=true
for target in "${TARGETS[@]}"; do
    if ! build_target "$target"; then
        success=false
    fi
done

# Build source distribution
echo ""
echo "📦 Building source distribution..."
maturin sdist --out dist

# Test builds (optional - won't fail if wheel is incompatible)
echo ""
echo "🧪 Testing macOS builds..."

# Detect current architecture
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" == "arm64" ]]; then
    COMPATIBLE_WHEEL_PATTERN="*-*-macosx*arm64.whl"
    PLATFORM_NAME="Apple Silicon (ARM64)"
elif [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    COMPATIBLE_WHEEL_PATTERN="*-*-macosx*x86_64.whl"
    PLATFORM_NAME="Intel (x86_64)"
else
    COMPATIBLE_WHEEL_PATTERN="*-*-macosx*.whl"
    PLATFORM_NAME="Unknown"
fi

echo "Current platform: $PLATFORM_NAME"

# Try to find a compatible wheel for testing
if ls dist/$COMPATIBLE_WHEEL_PATTERN 1> /dev/null 2>&1; then
    echo "🔍 Found compatible wheel for testing..."
    if pip install dist/$COMPATIBLE_WHEEL_PATTERN --force-reinstall 2>/dev/null; then
        echo "✅ Wheel installation successful"
        if $MODULE_NAME --help >/dev/null 2>&1 && python -m $MODULE_NAME --help >/dev/null 2>&1; then
            echo "✅ Wheel functionality test passed"
        else
            echo "⚠️  Wheel installed but functionality test failed (non-critical)"
        fi
    else
        echo "⚠️  Wheel installation failed (non-critical - may be platform incompatible)"
    fi
else
    echo "⚠️  No compatible wheel found for current platform (non-critical)"
    echo "    Available wheels:"
    ls dist/*.whl 2>/dev/null | sed 's/^/      /' || echo "      (No wheels found)"
fi

echo ""
if [ "$success" = true ]; then
    echo "✅ macOS build completed successfully!"
else
    echo "⚠️  macOS build completed with some failures"
fi

echo ""
echo "📁 Outputs:"
echo "   - Wheels: dist/*.whl"
echo "   - Source: dist/*.tar.gz"
echo "   - Binaries:"
ls -la muff-*-apple-darwin.tar.gz 2>/dev/null || echo "     (No binary archives created)"

echo ""
echo "🎯 Built targets:"
for target in "${TARGETS[@]}"; do
    if [[ -f "target/$target/release/muff" ]]; then
        echo "   ✅ $target"
    else
        echo "   ❌ $target (failed)"
    fi
done

# Clean up temporary files
echo "🔄 Cleaning up temporary files..."
python release/transform_readme_temp.py --action cleanup