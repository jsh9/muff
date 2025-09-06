# Simplified Windows build script for x86_64 with PowerShell
# Prerequisites: PowerShell, Python 3, Rust (see WINDOWS.md)

$ErrorActionPreference = "Stop"

$PACKAGE_NAME = "muff"
$MODULE_NAME = "muff"
$artifactsDir = if ($env:ARTIFACTS_DIR) { $env:ARTIFACTS_DIR } else { 'artifacts' }

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
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = "gcc"
    $env:CC_x86_64_pc_windows_gnu = "gcc"
    $env:CXX_x86_64_pc_windows_gnu = "g++"
}

# Install required toolchain for GNU target if MSVC not available
if (!$hasMSVC) {
    Write-Host "Installing MinGW-w64 toolchain..." -ForegroundColor Cyan

    # Check for common MinGW installations and add to PATH
    $mingwPaths = @(
        "C:\msys64\mingw64\bin",
        "C:\msys64\ucrt64\bin",
        "C:\mingw64\bin",
        "C:\ProgramData\chocolatey\lib\mingw\tools\install\mingw64\bin"
    )

    $mingwFound = $false
    foreach ($path in $mingwPaths) {
        if (Test-Path "$path\gcc.exe") {
            Write-Host "Found MinGW at: $path" -ForegroundColor Green
            $env:PATH = "$path;$env:PATH"
            $mingwFound = $true
            break
        }
    }

    if (!$mingwFound) {
        try {
            # Try to install via package managers
            if (Get-Command "scoop" -ErrorAction SilentlyContinue) {
                Write-Host "Installing MinGW via scoop..." -ForegroundColor Yellow
                scoop install mingw
                $env:PATH = "$env:USERPROFILE\scoop\apps\mingw\current\bin;$env:PATH"
            } elseif (Get-Command "choco" -ErrorAction SilentlyContinue) {
                Write-Host "Installing MinGW via chocolatey..." -ForegroundColor Yellow
                choco install mingw -y
                $env:PATH = "C:\ProgramData\chocolatey\lib\mingw\tools\install\mingw64\bin;$env:PATH"
            } else {
                Write-Host "Installing MSYS2 via winget..." -ForegroundColor Yellow
                winget install MSYS2.MSYS2 --silent
                Start-Sleep -Seconds 5

                # Install mingw-w64 toolchain in MSYS2
                Write-Host "Installing mingw-w64 toolchain in MSYS2..." -ForegroundColor Yellow
                & "C:\msys64\usr\bin\pacman.exe" -S --noconfirm mingw-w64-x86_64-toolchain

                $env:PATH = "C:\msys64\mingw64\bin;$env:PATH"
            }
            $mingwFound = $true
        } catch {
            Write-Host "Automatic installation failed" -ForegroundColor Red
        }
    }

    if (!$mingwFound -or !(Get-Command "gcc" -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: MinGW-w64 not found or not working" -ForegroundColor Red
        Write-Host "Please install MSYS2 manually:" -ForegroundColor Yellow
        Write-Host "  1. Run: winget install MSYS2.MSYS2" -ForegroundColor Yellow
        Write-Host "  2. Then run this script again" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "MinGW-w64 toolchain ready" -ForegroundColor Green

    # Set default Rust toolchain to GNU
    Write-Host "Setting default Rust target to GNU..." -ForegroundColor Yellow
    rustup default stable-x86_64-pc-windows-gnu
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
Remove-Item -Path "$artifactsDir\muff-*-pc-windows-*.tar.gz*" -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

# Prep README for PyPI with backup/restore
Write-Host "Preparing README for PyPI..." -ForegroundColor Cyan
$readme = Join-Path (Get-Location) 'README.md'
$readmeBackup = [System.IO.Path]::GetTempFileName()
if (Test-Path $readme) { Copy-Item $readme $readmeBackup -Force }
# Also register exit handler to restore on unexpected termination
try { Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action { if (Test-Path $using:readmeBackup) { Copy-Item $using:readmeBackup $using:readme -Force; Remove-Item $using:readmeBackup -Force } } | Out-Null } catch { }
python scripts\transform_readme.py --target pypi

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
        if ($Target -eq "x86_64-pc-windows-gnu") {
            $env:CARGO_BUILD_TARGET = $Target
        }
        maturin build --release --locked --target $Target --out dist
        Write-Host "SUCCESS: Wheel built for $Target" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Wheel build failed for $Target" -ForegroundColor Red
        return $false
    }

    # Build binary
    try {
        if ($Target -eq "x86_64-pc-windows-gnu") {
            $env:CARGO_BUILD_TARGET = $Target
        }
        cargo build --release --locked --target $Target
        Write-Host "SUCCESS: Binary built for $Target" -ForegroundColor Green

        # Create tar.gz archive in artifacts dir
        $archiveName = "muff-$Target"
        $tarFile = "$archiveName.tar.gz"

        $stageDir = Join-Path $env:TEMP ("muffstage_" + [System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $stageDir $archiveName) -Force | Out-Null
        Copy-Item "target\$Target\release\muff.exe" (Join-Path $stageDir "$archiveName\muff.exe")

        # Use built-in tar (bsdtar) available on modern Windows
        tar -C $stageDir -czf (Join-Path $artifactsDir $tarFile) $archiveName

        # Create checksum alongside archive
        $tarPath = Join-Path $artifactsDir $tarFile
        $hash = Get-FileHash $tarPath -Algorithm SHA256
        ($hash.Hash + '  ' + (Split-Path -Leaf $tarPath)) | Set-Content (Join-Path $artifactsDir ($tarFile + '.sha256')) -Encoding ascii

        Remove-Item -Path $stageDir -Recurse -Force
        Write-Host "Created: $tarPath" -ForegroundColor Green
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
Write-Host "   Binaries: $artifactsDir\muff-*-pc-windows-*.tar.gz"
Write-Host "   Checksums: $artifactsDir\*.sha256"

# Cleanup: restore README
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Cyan
if (Test-Path $readmeBackup) { Copy-Item $readmeBackup $readme -Force; Remove-Item $readmeBackup -Force }

Write-Host "SUCCESS: Done! See WINDOWS.md for next steps." -ForegroundColor Green
