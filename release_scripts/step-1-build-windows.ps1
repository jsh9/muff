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
$BINARY_NAME  = if ($env:BINARY_NAME)  { $env:BINARY_NAME }  else { 'muff' }
$ARCHIVE_PREFIX = if ($env:ARCHIVE_PREFIX) { $env:ARCHIVE_PREFIX } else { 'muff' }
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

# Test via module; __main__ resolves to the muff binary internally
& python -m $MODULE_NAME --help | Out-Null

Write-Host "==> Archiving standalone binary"
$archiveName = "$ARCHIVE_PREFIX-$TARGET_TRIPLE"
$archiveZip = "$archiveName.zip"
$binaryPath = Join-Path -Path "target/$TARGET_TRIPLE/release" -ChildPath "$BINARY_NAME.exe"
$artifactsDir = if ($env:ARTIFACTS_DIR) { $env:ARTIFACTS_DIR } else { 'artifacts' }
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
Compress-Archive -Path $binaryPath -DestinationPath (Join-Path $artifactsDir $archiveZip) -Force
$zipPath = Join-Path $artifactsDir $archiveZip
Get-FileHash $zipPath -Algorithm SHA256 | ForEach-Object { $_.Hash + '  ' + $archiveZip } | Set-Content (Join-Path $artifactsDir "$archiveZip.sha256")

Write-Host "==> Done"
