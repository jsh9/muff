#!/usr/bin/env zsh
set -euo pipefail

# Build wheels and archive binaries for macOS arm64. Optionally also build sdist.
#
# Usage:
#   release_scripts/step-1-build-macos.sh [--sdist]

PACKAGE_NAME_DEFAULT="muff"
MODULE_NAME_DEFAULT="ruff"
BINARY_NAME_DEFAULT="muff"
ARCHIVE_PREFIX_DEFAULT="muff"
TARGET_TRIPLE="aarch64-apple-darwin"

BUILD_SDIST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdist) BUILD_SDIST=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

function need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; } }
need python3
need cargo
need shasum
need maturin

read_version_py='import pathlib
try:
  import tomllib as tomli
except Exception:
  import tomli
cfg = tomli.loads(pathlib.Path("pyproject.toml").read_text())
print(cfg["project"]["version"])'
VERSION=$(python3 -c "$read_version_py")

PACKAGE_NAME=${PACKAGE_NAME:-$PACKAGE_NAME_DEFAULT}
MODULE_NAME=${MODULE_NAME:-$MODULE_NAME_DEFAULT}
BINARY_NAME=${BINARY_NAME:-$BINARY_NAME_DEFAULT}
ARCHIVE_PREFIX=${ARCHIVE_PREFIX:-$ARCHIVE_PREFIX_DEFAULT}

echo "==> Building wheel for $TARGET_TRIPLE (version $VERSION)"

# Temporarily transform README for PyPI, then restore on exit
READMETMP="$(mktemp)"
if [[ -f README.md ]]; then
  cp README.md "$READMETMP" || true
  trap 'if [[ -f "$READMETMP" ]]; then cp "$READMETMP" README.md 2>/dev/null || true; rm -f "$READMETMP"; fi' EXIT
fi
python3 scripts/transform_readme.py --target pypi || true
maturin build --release --locked --target "$TARGET_TRIPLE" --out dist

echo "==> Testing wheel"
python3 -m pip install dist/${PACKAGE_NAME}-*.whl --force-reinstall

# Test via module; __main__ now resolves to the muff binary internally
python3 -m "${MODULE_NAME}" --help >/dev/null

if [[ $BUILD_SDIST -eq 1 ]]; then
  echo "==> Building sdist"
  maturin sdist --out dist
fi

echo "==> Archiving standalone binary"
ARCHIVE_NAME="${ARCHIVE_PREFIX}-${TARGET_TRIPLE}"
ARCHIVE_FILE="${ARCHIVE_NAME}.tar.gz"
ARTIFACTS_DIR=${ARTIFACTS_DIR:-artifacts}
mkdir -p "$ARTIFACTS_DIR"

# stage directory for tar creation, then clean up
STAGE_DIR=$(mktemp -d)
mkdir -p "$STAGE_DIR/$ARCHIVE_NAME"
cp "target/${TARGET_TRIPLE}/release/${BINARY_NAME}" "$STAGE_DIR/$ARCHIVE_NAME/${BINARY_NAME}"
tar -C "$STAGE_DIR" -czf "$ARTIFACTS_DIR/$ARCHIVE_FILE" "$ARCHIVE_NAME"
shasum -a 256 "$ARTIFACTS_DIR/$ARCHIVE_FILE" > "$ARTIFACTS_DIR/$ARCHIVE_FILE.sha256"
rm -rf "$STAGE_DIR"

echo "==> Done"
