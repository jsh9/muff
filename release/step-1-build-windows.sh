#!/bin/bash
set -euo pipefail

# Windows cross-compilation build script (from macOS)

PACKAGE_NAME="muff"
MODULE_NAME="muff"

echo "🪟 Building muff for Windows (cross-compilation from macOS)..."

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

# Install Windows targets
echo "🎯 Installing Rust targets for Windows..."
rustup target add x86_64-pc-windows-gnu
rustup target add x86_64-pc-windows-msvc

# Check for cross-compilation tools
if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo "📦 Windows cross-compilation tools not found. Installing recommendations:"
    echo ""
    echo "Option 1 - Install mingw-w64:"
    echo "   brew install mingw-w64"
    echo ""
    echo "Option 2 - Use cargo-cross (recommended):"
    echo "   cargo install cross"
    echo "   Then this script will use 'cross' instead of 'cargo'"
    echo ""
    
    if ! command -v cross &> /dev/null; then
        echo "⚠️  Neither mingw-w64 nor 'cross' found"
        echo "Will attempt to build anyway, but may fail"
        USE_CROSS=false
    else
        echo "✅ Found 'cross' tool, will use it for cross-compilation"
        USE_CROSS=true
    fi
else
    echo "✅ Found mingw-w64 toolchain"
    USE_CROSS=false
fi

# Check for zip command
if ! command -v zip &> /dev/null; then
    echo "📦 Installing zip command..."
    # zip should be available on macOS by default, but just in case
    if command -v brew &> /dev/null; then
        brew install zip || true
    fi
fi

# Clean previous builds
echo "🧹 Cleaning previous Windows builds..."
rm -rf target/x86_64-pc-windows-gnu/release/
rm -rf target/x86_64-pc-windows-msvc/release/
rm -f muff-*-pc-windows-*.zip*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
python release/transform_readme_temp.py --action create

# Define Windows targets
declare -a TARGETS=(
    "x86_64-pc-windows-gnu"
    "x86_64-pc-windows-msvc"
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
        build_cmd="cross build --release --locked --target $target"
    else
        build_cmd="cargo build --release --locked --target $target"
    fi
    
    if $build_cmd; then
        echo "✅ Binary built successfully for $target"
        
        # Create archive
        archive_name="muff-$target"
        archive_file="$archive_name.zip"
        
        mkdir -p "$archive_name"
        cp "target/$target/release/muff.exe" "$archive_name/muff.exe"
        
        if command -v zip &> /dev/null; then
            zip -r "$archive_file" "$archive_name"
            
            # Create checksum
            shasum -a 256 "$archive_file" > "$archive_file.sha256"
            
            echo "📦 Created: $archive_file"
        else
            echo "⚠️  zip command not found, skipping archive creation for $target"
        fi
        
        # Clean up
        rm -rf "$archive_name"
        
    else
        echo "❌ Binary build failed for $target"
        echo "💡 Make sure you have Windows cross-compilation tools installed"
        return 1
    fi
}

# Build for all Windows targets
success=true
for target in "${TARGETS[@]}"; do
    if ! build_target "$target"; then
        success=false
    fi
done

echo ""
if [ "$success" = true ]; then
    echo "✅ Windows cross-compilation completed successfully!"
else
    echo "⚠️  Windows cross-compilation completed with some failures"
fi

echo ""
echo "📁 Outputs:"
echo "   - Wheels: dist/*.whl (if successful)"
echo "   - Binaries:"
ls -la muff-*-pc-windows-*.zip 2>/dev/null || echo "     (No binary archives created)"

echo ""
echo "🎯 Built targets:"
for target in "${TARGETS[@]}"; do
    if [[ -f "target/$target/release/muff.exe" ]]; then
        echo "   ✅ $target"
    else
        echo "   ❌ $target (failed)"
    fi
done

# Test builds (optional - cross-compiled wheels likely won't work on macOS)
echo ""
echo "🧪 Testing Windows builds..."
echo "⚠️  Note: Cross-compiled Windows wheels likely won't install on macOS (this is normal)"

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
        echo "⚠️  Wheel installation failed (expected for cross-compiled Windows wheels)"
    fi
else
    echo "⚠️  No wheels found (normal for cross-compilation)"
fi

echo ""
echo "💡 Notes:"
echo "   - Cross-compiled Windows binaries should be tested on actual Windows systems"
echo "   - Cross-compiled wheels may not install on macOS (this is expected and not an error)"
echo "   - MSVC target may require additional setup"
echo "   - GNU target is generally more reliable for cross-compilation"

# Clean up temporary files
echo ""
echo "🔄 Cleaning up temporary files..."
python release/transform_readme_temp.py --action cleanup