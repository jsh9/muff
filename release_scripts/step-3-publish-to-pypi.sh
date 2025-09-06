#!/usr/bin/env zsh
set -euo pipefail

# Upload wheels/sdists to PyPI from a local directory.
#
# Usage:
#   release_scripts/step-3-publish-to-pypi.sh [--path dist] [--include-sdist]

DIR="dist"
INCLUDE_SDIST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      DIR="$2"; shift 2 ;;
    --include-sdist)
      INCLUDE_SDIST=1; shift ;;
    *)
      echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$DIR" ]]; then
  echo "Directory not found: $DIR" >&2; exit 1
fi

FILES=($DIR/*.whl)
if [[ $INCLUDE_SDIST -eq 1 ]]; then
  FILES+=($DIR/*.tar.gz(N))
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No artifacts found in $DIR" >&2; exit 1
fi

if command -v twine >/dev/null 2>&1; then
  python -m pip install -U twine >/dev/null
  twine upload $FILES
else
  if ! command -v maturin >/dev/null 2>&1; then
    echo "Need either twine or maturin installed." >&2; exit 1
  fi
  maturin upload $FILES
fi

echo "Uploaded ${#FILES[@]} file(s) from $DIR to PyPI."

