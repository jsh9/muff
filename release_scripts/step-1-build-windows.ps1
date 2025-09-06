# Build wheel and archive binary for Windows x86_64 (MSVC)
# Usage:
#   release_scripts/step-1-build-windows.ps1

Param()

$ErrorActionPreference = 'Stop'

function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Error "Missing required command: $cmd"
  }
}

Need python
Need cargo
Need maturin

$PACKAGE_NAME = if ($env:PACKAGE_NAME) { $env:PACKAGE_NAME } else { 'muff' }
$MODULE_NAME  = if ($env:MODULE_NAME)  { $env:MODULE_NAME }  else { 'ruff' }
$BINARY_NAME  = if ($env:BINARY_NAME)  { $env:BINARY_NAME }  else { 'ruff' }
$ARCHIVE_PREFIX = if ($env:ARCHIVE_PREFIX) { $env:ARCHIVE_PREFIX } else { 'ruff' }
$TARGET_TRIPLE = 'x86_64-pc-windows-msvc'

$readVersion = @'
import pathlib
try:
    import tomllib as tomli
except Exception:
    import tomli
data = pathlib.Path("pyproject.toml").read_text()
cfg = tomli.loads(data)
print(cfg["project"]["version"]) 
'@

$VERSION = (& python - << $readVersion).Trim()

Write-Host "==> Building wheel for $TARGET_TRIPLE (version $VERSION)"
try { & python scripts/transform_readme.py --target pypi | Out-Null } catch { }
& maturin build --release --locked --target $TARGET_TRIPLE --out dist

Write-Host "==> Testing wheel"
& python -m pip install dist/${PACKAGE_NAME}-*.whl --force-reinstall
& $BINARY_NAME --help | Out-Null
& python -m $MODULE_NAME --help | Out-Null

Write-Host "==> Archiving standalone binary"
$archiveName = "$ARCHIVE_PREFIX-$TARGET_TRIPLE"
$archiveZip = "$archiveName.zip"
$binaryPath = Join-Path -Path "target/$TARGET_TRIPLE/release" -ChildPath "$BINARY_NAME.exe"
if (Test-Path $archiveZip) { Remove-Item $archiveZip -Force }
Compress-Archive -Path $binaryPath -DestinationPath $archiveZip
Get-FileHash $archiveZip -Algorithm SHA256 | ForEach-Object { $_.Hash + '  ' + $archiveZip } | Set-Content "$archiveZip.sha256"

Write-Host "==> Done"

