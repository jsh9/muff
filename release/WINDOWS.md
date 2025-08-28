# Windows Release Instructions

Instructions for building Muff on Windows x86_64 with PowerShell.

## Prerequisites

1. **PowerShell 7** (recommended)
   ```powershell
   winget install Microsoft.PowerShell
   ```
   Or use built-in Windows PowerShell 5.1

2. **Python 3**
   ```powershell
   winget install -e --id Python.Python.3.11 --scope machine
   ```
   Or download from: https://python.org

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

1. **Open PowerShell** as Administrator (recommended)

2. **Navigate to project directory**
   ```powershell
   cd C:\path\to\muff
   ```

3. **Run the Windows build script**
   ```powershell
   .\release\step-1-build-windows-simple.ps1
   ```

## What the script does

1. Installs Python virtual environment and maturin
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

- **Missing Python**: Install from python.org or use winget
- **Missing Rust**: Install from rustup.rs or use winget
- **MSVC build fails**: Install Visual Studio Build Tools, or script will fallback to GNU target
- **Permission errors**: Run PowerShell as Administrator
- **Execution policy**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## Next Steps

After building, use the release scripts:
```powershell
.\release\step-2-create-release.ps1 v1.0.0
.\release\step-3-publish-pypi.ps1
```