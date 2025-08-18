#!/bin/bash
set -euo pipefail

# Windows native build script
# Run this script on a Windows machine with WSL/Git Bash/MSYS2

PACKAGE_NAME="muff"
MODULE_NAME="muff"

echo "🪟 Building muff natively on Windows..."

# Function to check if running on Windows
check_windows() {
    if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && ! -f "/proc/version" ]]; then
        echo "❌ This script should be run on Windows with WSL, Git Bash, or MSYS2"
        echo "💡 Current OSTYPE: $OSTYPE"
        exit 1
    fi
    
    # Check if we're in WSL
    if [[ -f "/proc/version" ]] && grep -q Microsoft /proc/version; then
        echo "✅ Detected Windows Subsystem for Linux (WSL)"
        WINDOWS_ENV="wsl"
    elif [[ "$OSTYPE" == "msys" ]]; then
        echo "✅ Detected MSYS2/Git Bash environment"
        WINDOWS_ENV="msys"
    else
        echo "✅ Detected Windows environment"
        WINDOWS_ENV="windows"
    fi
}

# Function to install packages with user consent (WSL/Ubuntu)
install_package_wsl() {
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

# Function to check for required commands
check_command() {
    local cmd=$1
    local install_hint=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ $cmd is required but not installed"
        echo "💡 $install_hint"
        return 1
    else
        echo "✅ Found $cmd"
        return 0
    fi
}

# Check environment
check_windows

echo "🔍 Checking dependencies..."

# Check Python 3
if [[ "$WINDOWS_ENV" == "wsl" ]]; then
    # WSL environment - use apt
    if ! command -v python3 &> /dev/null; then
        if ! install_package_wsl "python3 python3-pip python3-venv build-essential" "Python 3 and development tools"; then
            exit 1
        fi
    fi
    
    # Check python3-venv specifically
    if ! python3 -m venv --help &> /dev/null; then
        if ! install_package_wsl "python3-venv" "python3-venv package"; then
            exit 1
        fi
    fi
    
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
else
    # Native Windows (MSYS2/Git Bash)
    if ! check_command "python" "Install Python from https://python.org or use 'winget install Python.Python.3'"; then
        exit 1
    fi
    
    if ! check_command "pip" "Python pip should be included with Python installation"; then
        exit 1
    fi
    
    PYTHON_CMD="python"
    PIP_CMD="pip"
fi

# Check Rust/Cargo
if ! command -v cargo &> /dev/null; then
    echo "📦 Rust/Cargo is required but not installed"
    echo "Installing Rust via rustup..."
    
    if [[ "$WINDOWS_ENV" == "wsl" ]]; then
        # WSL - use curl
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
            source ~/.cargo/env
            echo "✅ Successfully installed Rust"
        else
            echo "❌ Failed to install Rust"
            echo "💡 Please install manually: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            exit 1
        fi
    else
        # Native Windows - use rustup-init.exe
        echo "💡 Please install Rust manually:"
        echo "   1. Download and run: https://rustup.rs/"
        echo "   2. Or use: winget install Rustlang.Rustup"
        echo "   3. Restart your terminal after installation"
        exit 1
    fi
fi

# Ensure cargo is in PATH
if ! command -v cargo &> /dev/null; then
    if [[ -f ~/.cargo/env ]]; then
        source ~/.cargo/env
    fi
fi

# Check Visual Studio Build Tools (required for MSVC target on Windows)
if [[ "$WINDOWS_ENV" != "wsl" ]]; then
    echo "🔍 Checking for Visual Studio Build Tools..."
    
    # Check for cl.exe (MSVC compiler)
    if ! command -v cl.exe &> /dev/null 2>&1; then
        echo "⚠️  Visual Studio Build Tools not found in PATH"
        echo "💡 For best results on Windows, install:"
        echo "   - Visual Studio Build Tools: https://visualstudio.microsoft.com/downloads/"
        echo "   - Or Visual Studio Community with C++ tools"
        echo "   - This enables the MSVC target (x86_64-pc-windows-msvc)"
        echo ""
        echo "Continuing with GNU target only..."
    else
        echo "✅ Found Visual Studio Build Tools"
    fi
fi

# Create virtual environment for build tools
if [[ "$WINDOWS_ENV" == "wsl" ]]; then
    VENV_DIR="$HOME/.muff-build-env"
else
    VENV_DIR="$HOME/.muff-build-env"
fi

echo "📦 Setting up build environment..."

if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment at $VENV_DIR..."
    if ! $PYTHON_CMD -m venv "$VENV_DIR"; then
        echo "❌ Failed to create virtual environment"
        exit 1
    fi
fi

# Activate virtual environment
echo "Activating virtual environment..."
if [[ "$WINDOWS_ENV" == "wsl" ]]; then
    source "$VENV_DIR/bin/activate"
else
    source "$VENV_DIR/Scripts/activate" 2>/dev/null || source "$VENV_DIR/bin/activate"
fi

# Install/upgrade maturin in virtual environment
echo "Installing maturin in virtual environment..."
$PIP_CMD install --upgrade pip maturin

# Verify installation
if ! command -v maturin &> /dev/null; then
    echo "❌ Failed to install maturin in virtual environment"
    exit 1
fi

echo "✅ Build environment ready (using virtual environment)"

# Detect current architecture and set targets
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" == "x86_64" ]]; then
    PLATFORM_NAME="x86_64 (64-bit)"
    # Prefer MSVC if available, fallback to GNU
    TARGETS=("x86_64-pc-windows-msvc" "x86_64-pc-windows-gnu")
else
    echo "❌ Unsupported architecture: $CURRENT_ARCH"
    echo "💡 This script supports x86_64 Windows only"
    exit 1
fi

echo "🏗️  Detected platform: Windows $PLATFORM_NAME"

# Install Rust targets
echo "🎯 Installing Rust targets..."
for target in "${TARGETS[@]}"; do
    echo "Installing target: $target"
    rustup target add "$target"
done

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf dist/
for target in "${TARGETS[@]}"; do
    rm -rf "target/$target/release/"
done
rm -f muff-*-pc-windows-*.zip*

# Prep README.md for PyPI (create temporary copy to avoid git diff)
echo "📝 Preparing README.md for PyPI..."
$PYTHON_CMD release/transform_readme_temp.py --action create

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
        echo "⚠️  Wheel build failed for $target"
    fi
    
    # Build binary with cargo
    echo "🔧 Building binary for $target..."
    if cargo build --release --locked --target "$target"; then
        echo "✅ Binary built successfully for $target"
        
        # Create archive
        archive_name="muff-$target"
        archive_file="$archive_name.zip"
        
        mkdir -p "$archive_name"
        cp "target/$target/release/muff.exe" "$archive_name/muff.exe"
        
        # Create zip archive
        if command -v zip &> /dev/null; then
            zip -r "$archive_file" "$archive_name"
        elif command -v 7z &> /dev/null; then
            7z a "$archive_file" "$archive_name"
        elif command -v powershell.exe &> /dev/null; then
            powershell.exe -Command "Compress-Archive -Path '$archive_name' -DestinationPath '$archive_file'"
        else
            echo "⚠️  No zip utility found, skipping archive creation for $target"
            rm -rf "$archive_name"
            return 0
        fi
        
        # Create checksum
        if command -v sha256sum &> /dev/null; then
            sha256sum "$archive_file" > "$archive_file.sha256"
        elif command -v shasum &> /dev/null; then
            shasum -a 256 "$archive_file" > "$archive_file.sha256"
        elif command -v powershell.exe &> /dev/null; then
            powershell.exe -Command "Get-FileHash '$archive_file' -Algorithm SHA256 | Select-Object -ExpandProperty Hash" > "$archive_file.sha256"
        fi
        
        # Clean up
        rm -rf "$archive_name"
        
        echo "📦 Created: $archive_file"
        return 0
    else
        echo "❌ Binary build failed for $target"
        if [[ "$target" == "x86_64-pc-windows-msvc" ]]; then
            echo "💡 MSVC target requires Visual Studio Build Tools"
            echo "   Install from: https://visualstudio.microsoft.com/downloads/"
        fi
        return 1
    fi
}

# Build source distribution
echo ""
echo "📦 Building source distribution..."
maturin sdist --out dist

# Build for all targets
success=true
built_targets=()
for target in "${TARGETS[@]}"; do
    if build_target "$target"; then
        built_targets+=("$target")
    else
        success=false
        echo "⚠️  Build failed for $target (continuing...)"
    fi
done

# Test builds (native architecture only)
echo ""
echo "🧪 Testing Windows builds..."

# Find compatible wheel for current architecture
if ls dist/*-*-win_amd64.whl 1> /dev/null 2>&1; then
    echo "🔍 Found compatible wheel for testing..."
    
    WHEEL_FILE=$(ls dist/*-*-win_amd64.whl | head -1)
    
    # Install and test in the build virtual environment
    echo "Installing wheel in virtual environment for testing..."
    if $PIP_CMD install "$WHEEL_FILE" --force-reinstall; then
        echo "✅ Wheel installation successful"
        
        # Test functionality in the virtual environment
        if $MODULE_NAME --help >/dev/null 2>&1 && $PYTHON_CMD -m $MODULE_NAME --help >/dev/null 2>&1; then
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
    echo "✅ Windows build completed successfully!"
else
    echo "⚠️  Windows build completed with some failures"
fi

echo ""
echo "📁 Outputs:"
echo "   - Wheels: dist/*.whl"
echo "   - Source: dist/*.tar.gz"
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

echo ""
echo "💡 Notes:"
echo "   - All prerequisites automatically checked with user guidance"
echo "   - Native build for Windows x86_64 attempted"
echo "   - MSVC target preferred but requires Visual Studio Build Tools"
echo "   - GNU target works with MSYS2/MinGW toolchain"
echo "   - Test binaries thoroughly before releasing"
echo "   - Build environment isolated in virtual environment: $VENV_DIR"

# Clean up temporary files
echo ""
echo "🔄 Cleaning up temporary files..."
$PYTHON_CMD release/transform_readme_temp.py --action cleanup