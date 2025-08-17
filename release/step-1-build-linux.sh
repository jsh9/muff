#!/bin/bash
set -euo pipefail

# Linux cross-compilation build script (from macOS)

PACKAGE_NAME="muff"
MODULE_NAME="muff"

echo "🐧 Building muff for Linux (cross-compilation from macOS)..."

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo "❌ Rust/Cargo is required but not installed"
    exit 1
fi

if ! command -v pip &> /dev/null; then
    echo "❌ pip is required but not installed"
    exit 1
fi

# Install maturin if not available
if ! command -v maturin &> /dev/null; then
    echo "📦 Installing maturin..."
    pip install maturin
fi

# Install Linux targets
echo "🎯 Installing Rust targets for Linux..."
rustup target add x86_64-unknown-linux-gnu
rustup target add aarch64-unknown-linux-gnu

# Check for cross-compilation tools
echo "🔍 Checking cross-compilation setup..."

if command -v cross &> /dev/null; then
    CROSS_VERSION=$(cross --version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    echo "✅ Found 'cross' tool (version: $CROSS_VERSION)"
    
    # Test if cross works properly
    echo "🧪 Testing cross compatibility..."
    if cross --version >/dev/null 2>&1; then
        echo "✅ Cross appears to be working, will attempt to use it"
        USE_CROSS=true
    else
        echo "⚠️  Cross found but may have issues, will try anyway"
        USE_CROSS=true
    fi
elif command -v x86_64-linux-gnu-gcc &> /dev/null; then
    echo "✅ Found cross-compilation toolchains"
    USE_CROSS=false
else
    echo "📦 Cross-compilation tools not found."
    echo ""
    echo "To enable Linux cross-compilation, install one of:"
    echo ""
    echo "Option 1 - Update cargo-cross (recommended):"
    echo "   cargo install --force cross"
    echo ""
    echo "Option 2 - Install cross-compilation toolchains:"
    echo "   brew install messense/macos-cross-toolchains/x86_64-unknown-linux-gnu"
    echo "   brew install messense/macos-cross-toolchains/aarch64-unknown-linux-gnu"
    echo ""
    echo "⚠️  Continuing without cross-compilation (will likely fail)"
    echo "Press Ctrl+C to cancel or Enter to continue anyway..."
    read -r
    USE_CROSS=false
fi

# Clean previous builds
echo "🧹 Cleaning previous Linux builds..."
rm -rf target/x86_64-unknown-linux-gnu/release/
rm -rf target/aarch64-unknown-linux-gnu/release/
rm -f muff-*-unknown-linux-gnu.tar.gz*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
python release/transform_readme_temp.py --action create

# Define Linux targets
declare -a TARGETS=(
    "x86_64-unknown-linux-gnu"
    "aarch64-unknown-linux-gnu"
)

# Build function for each target
build_target() {
    local target=$1
    echo ""
    echo "🏗️  Building for $target..."
    
    # Build with maturin (may fail for cross-compilation)
    echo "🛠️  Building wheel for $target..."
    if maturin build --release --locked --target "$target" --out dist 2>/dev/null; then
        echo "✅ Wheel built successfully for $target"
    else
        echo "⚠️  Wheel build failed for $target (normal for cross-compilation)"
    fi
    
    # Build binary with cargo or cross
    echo "🔧 Building binary for $target..."
    if [ "$USE_CROSS" = true ]; then
        echo "Using cross for compilation..."
        if cross build --release --locked --target "$target" 2>&1; then
            build_success=true
        else
            echo "⚠️  Cross compilation failed, trying with regular cargo..."
            if cargo build --release --locked --target "$target" 2>&1; then
                build_success=true
            else
                build_success=false
            fi
        fi
    else
        echo "Using cargo for compilation..."
        if cargo build --release --locked --target "$target" 2>&1; then
            build_success=true
        else
            build_success=false
        fi
    fi
    
    if [ "$build_success" = true ]; then
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
        echo "💡 Make sure you have cross-compilation tools installed"
        return 1
    fi
}

# Build for all Linux targets
success=true
for target in "${TARGETS[@]}"; do
    if ! build_target "$target"; then
        success=false
    fi
done

echo ""
if [ "$success" = true ]; then
    echo "✅ Linux cross-compilation completed successfully!"
else
    echo "⚠️  Linux cross-compilation completed with some failures"
fi

echo ""
echo "📁 Outputs:"
echo "   - Wheels: dist/*.whl (if successful)"
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

# Test builds (optional - cross-compiled wheels likely won't work on macOS)
echo ""
echo "🧪 Testing Linux builds..."
echo "⚠️  Note: Cross-compiled Linux wheels likely won't install on macOS (this is normal)"

if ls dist/*.whl 1> /dev/null 2>&1; then
    echo "🔍 Found wheels, attempting installation test..."
    # Try to install any wheel, but don't fail if it doesn't work
    if pip install dist/*.whl --force-reinstall 2>/dev/null; then
        echo "✅ Wheel installation successful (unexpected but good!)"
        if $MODULE_NAME --help >/dev/null 2>&1 && python -m $MODULE_NAME --help >/dev/null 2>&1; then
            echo "✅ Wheel functionality test passed"
        else
            echo "⚠️  Wheel installed but functionality test failed (non-critical)"
        fi
    else
        echo "⚠️  Wheel installation failed (expected for cross-compiled Linux wheels)"
    fi
else
    echo "⚠️  No wheels found (normal for cross-compilation)"
fi

echo ""
echo "💡 Notes:"
echo "   - Cross-compiled binaries should be tested on actual Linux systems"
echo "   - Wheels may not install on macOS (this is expected and not an error)"

# Clean up temporary files
echo ""
echo "🔄 Cleaning up temporary files..."
python release/transform_readme_temp.py --action cleanup