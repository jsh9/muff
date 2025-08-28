# Simplified Windows build script for x86_64 with PowerShell
# Prerequisites: PowerShell, Python 3, Rust (see WINDOWS.md)

$ErrorActionPreference = "Stop"

$PACKAGE_NAME = "muff"
$MODULE_NAME = "muff"

Write-Host "Building muff for Windows x86_64..." -ForegroundColor Green

# Function to check required tools
function Test-Command {
    param([string]$Command, [string]$InstallHint)
    
    if (!(Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: $Command not found. Please install $InstallHint" -ForegroundColor Red
        exit 1
    }
    Write-Host "Found $Command" -ForegroundColor Green
}

Write-Host "Checking prerequisites..." -ForegroundColor Cyan
Test-Command "python" "Python 3 from python.org or 'winget install Python.Python.3.11'"
Test-Command "pip" "Python pip (included with Python)"
Test-Command "cargo" "Rust from rustup.rs or 'winget install Rustlang.Rustup'"

# Create and activate virtual environment
$VENV_DIR = "$env:USERPROFILE\.muff-build-env"
Write-Host "Setting up build environment..." -ForegroundColor Cyan

if (!(Test-Path $VENV_DIR)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv "$VENV_DIR"
}

Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& "$VENV_DIR\Scripts\Activate.ps1"

# Install maturin
Write-Host "Installing maturin..." -ForegroundColor Yellow
pip install --upgrade pip maturin

# Check for Visual Studio Build Tools and set targets accordingly
Write-Host "Checking for Visual Studio Build Tools..." -ForegroundColor Cyan
$hasMSVC = $false
try {
    $null = Get-Command "cl.exe" -ErrorAction Stop
    $hasMSVC = $true
    Write-Host "Found Visual Studio Build Tools (MSVC available)" -ForegroundColor Green
} catch {
    Write-Host "Visual Studio Build Tools not found in PATH" -ForegroundColor Yellow
    Write-Host "HINT: Install from https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    Write-Host "Will use GNU target only" -ForegroundColor Yellow
}

# Set Windows targets based on available toolchain
if ($hasMSVC) {
    $TARGETS = @("x86_64-pc-windows-msvc", "x86_64-pc-windows-gnu")
    Write-Host "Targets: MSVC (preferred) + GNU (fallback)" -ForegroundColor Green
} else {
    $TARGETS = @("x86_64-pc-windows-gnu")
    Write-Host "Targets: GNU only (MSVC not available)" -ForegroundColor Yellow
    # Force GNU toolchain when MSVC not available
    Write-Host "Setting GNU toolchain environment..." -ForegroundColor Yellow
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = "x86_64-w64-mingw32-gcc"
    $env:CC_x86_64_pc_windows_gnu = "x86_64-w64-mingw32-gcc"
    $env:CXX_x86_64_pc_windows_gnu = "x86_64-w64-mingw32-g++"
}

# Install required toolchain for GNU target if MSVC not available
if (!$hasMSVC) {
    Write-Host "Installing MinGW-w64 toolchain..." -ForegroundColor Cyan
    try {
        # Try to install via scoop (common package manager)
        if (Get-Command "scoop" -ErrorAction SilentlyContinue) {
            scoop install mingw
        } elseif (Get-Command "choco" -ErrorAction SilentlyContinue) {
            # Try chocolatey
            choco install mingw -y
        } else {
            Write-Host "Please install MinGW-w64 manually:" -ForegroundColor Red
            Write-Host "  Option 1: Install MSYS2: winget install MSYS2.MSYS2" -ForegroundColor Yellow
            Write-Host "  Option 2: Download from: https://www.mingw-w64.org/downloads/" -ForegroundColor Yellow
            Write-Host "  Then add the bin directory to your PATH" -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Host "Failed to install MinGW-w64 automatically" -ForegroundColor Red
        Write-Host "Please install manually and ensure gcc is in PATH" -ForegroundColor Yellow
        exit 1
    }
}

# Install Rust targets
Write-Host "Installing Rust targets..." -ForegroundColor Cyan
foreach ($target in $TARGETS) {
    Write-Host "Installing target: $target" -ForegroundColor Yellow
    rustup target add $target
}

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Cyan
Remove-Item -Path "dist" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "target\*\release" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "muff-*-pc-windows-*.zip*" -Force -ErrorAction SilentlyContinue

# Prep README for PyPI
Write-Host "Preparing README for PyPI..." -ForegroundColor Cyan
python release\transform_readme_temp.py --action create

# Build source distribution
Write-Host "Building source distribution..." -ForegroundColor Cyan
maturin sdist --out dist

# Function to build for a specific target
function Build-Target {
    param([string]$Target)
    
    Write-Host ""
    Write-Host "Building for $Target..." -ForegroundColor Green
    
    # Build wheel
    try {
        maturin build --release --locked --target $Target --out dist
        Write-Host "SUCCESS: Wheel built for $Target" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Wheel build failed for $Target" -ForegroundColor Red
        return $false
    }
    
    # Build binary
    try {
        cargo build --release --locked --target $Target
        Write-Host "SUCCESS: Binary built for $Target" -ForegroundColor Green
        
        # Create zip archive
        $archiveName = "muff-$Target"
        $archiveFile = "$archiveName.zip"
        
        New-Item -ItemType Directory -Path $archiveName -Force | Out-Null
        Copy-Item "target\$Target\release\muff.exe" "$archiveName\"
        
        # Create zip
        Compress-Archive -Path $archiveName -DestinationPath $archiveFile -Force
        
        # Create checksum
        $hash = Get-FileHash $archiveFile -Algorithm SHA256
        $hash.Hash | Out-File "$archiveFile.sha256" -Encoding ascii
        
        Remove-Item -Path $archiveName -Recurse -Force
        Write-Host "Created: $archiveFile" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "ERROR: Binary build failed for $Target" -ForegroundColor Red
        if ($Target -eq "x86_64-pc-windows-msvc") {
            Write-Host "HINT: Install Visual Studio Build Tools for MSVC support" -ForegroundColor Yellow
        }
        return $false
    }
}

# Build for all targets
$successCount = 0
foreach ($target in $TARGETS) {
    if (Build-Target $target) {
        $successCount++
    }
    else {
        Write-Host "WARNING: Build failed for $target (continuing...)" -ForegroundColor Yellow
    }
}

# Test the build
Write-Host ""
Write-Host "Testing build..." -ForegroundColor Cyan
$wheelFiles = Get-ChildItem -Path "dist" -Filter "*-*-win_amd64.whl"
if ($wheelFiles.Count -gt 0) {
    $wheelFile = $wheelFiles[0].FullName
    Write-Host "Testing wheel: $wheelFile" -ForegroundColor Yellow
    
    try {
        pip install $wheelFile --force-reinstall
        & $MODULE_NAME --help | Out-Null
        Write-Host "SUCCESS: Wheel test passed" -ForegroundColor Green
    }
    catch {
        Write-Host "WARNING: Wheel test failed" -ForegroundColor Yellow
    }
}
else {
    Write-Host "WARNING: No wheel found for testing" -ForegroundColor Yellow
}

# Summary
Write-Host ""
if ($successCount -gt 0) {
    Write-Host "SUCCESS: Windows build completed! ($successCount targets succeeded)" -ForegroundColor Green
}
else {
    Write-Host "ERROR: All builds failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Output files:" -ForegroundColor Cyan
Write-Host "   Wheels: dist\*.whl"
Write-Host "   Binaries: muff-*-pc-windows-*.zip"
Write-Host "   Checksums: *.sha256"

# Cleanup
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Cyan
python release\transform_readme_temp.py --action cleanup

Write-Host "SUCCESS: Done! See WINDOWS.md for next steps." -ForegroundColor Green