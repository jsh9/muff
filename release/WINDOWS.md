# Windows Release Instructions

Instructions for building Muff on Windows x86_64 with PowerShell.

## Prerequisites

1. **PowerShell 7** (recommended)
   ```powershell
   winget install Microsoft.PowerShell
   ```
   Or use built-in Windows PowerShell 5.1

2. **Anaconda**
   ```powershell
   winget install Anaconda.Anaconda3
   ```
   Or download from: https://www.anaconda.com/download
   
   After installation, use **Anaconda PowerShell Prompt** instead of regular PowerShell for all subsequent commands.

3. **Rust**
   ```powershell
   winget install Rustlang.Rustup
   ```
   Or download from: https://rustup.rs/

4. **Visual Studio Build Tools** (recommended)
   - Download from: https://visualstudio.microsoft.com/downloads/
   - Select "C++ build tools" during installation
   - This enables the MSVC target for better Windows compatibility

## Build Process

1. **Open Anaconda PowerShell Prompt** as Administrator (recommended)
   - Search for "Anaconda PowerShell Prompt" in Windows Start menu
   - Right-click and select "Run as administrator"

2. **Navigate to project directory**
   ```powershell
   cd C:\path\to\muff
   ```

3. **Run the Windows build script**
   ```powershell
   .\release\step-1-build-windows-simple.ps1
   ```

## What the script does

1. Uses Anaconda's Python environment and installs maturin
2. Adds Windows Rust targets (MSVC preferred, GNU fallback)
3. Builds Python wheels and standalone binaries
4. Creates zip archives with checksums
5. Tests the built wheel

## Output

After successful build:
- **Wheels**: `dist/*.whl` (for PyPI)
- **Binaries**: `muff-x86_64-pc-windows-*.zip` (standalone executables)
- **Source**: `dist/*.tar.gz`

## Troubleshooting

- **Missing Anaconda**: Install from anaconda.com or use winget
- **Python environment issues**: Ensure you're using Anaconda PowerShell Prompt, not regular PowerShell
- **Missing Rust**: Install from rustup.rs or use winget
- **MSVC build fails**: Install Visual Studio Build Tools, or script will fallback to GNU target
- **Permission errors**: Run Anaconda PowerShell Prompt as Administrator
- **Execution policy**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## Next Steps

After building, use the release scripts:
```powershell
.\release\step-2-create-release.ps1 v1.0.0
.\release\step-3-publish-pypi.ps1
```