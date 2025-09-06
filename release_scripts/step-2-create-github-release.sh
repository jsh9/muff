#!/usr/bin/env zsh
set -euo pipefail

# Create or update a GitHub release and upload provided assets.
#
# Usage:
#   release_scripts/step-2-create-github-release.sh --tag vX.Y.Z [--assets file1 ...]
# If --assets is omitted, uploads any of: ruff-*.tar.gz, ruff-*.zip and their .sha256 in CWD.

function need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; } }
need gh

TAG=""
ASSETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"; shift 2 ;;
    --assets)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        ASSETS+="$1"; shift
      done ;;
    *)
      echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "--tag is required" >&2; exit 2
fi

if [[ ${#ASSETS[@]} -eq 0 ]]; then
  ASSETS=(ruff-*.tar.gz ruff-*.zip ruff-*.tar.gz.sha256 ruff-*.zip.sha256)
fi

EXISTING=0
if gh release view "$TAG" >/dev/null 2>&1; then EXISTING=1; fi

FOUND=()
for p in "$ASSETS[@]"; do
  for f in ${(~)p}; do
    [[ -f "$f" ]] && FOUND+="$f"
  done
done

if [[ ${#FOUND[@]} -eq 0 ]]; then
  echo "No assets found to upload." >&2; exit 1
fi

if [[ $EXISTING -eq 1 ]]; then
  gh release upload "$TAG" "$FOUND[@]" --clobber
else
  gh release create "$TAG" "$FOUND[@]" --title "$TAG" --notes "Release $TAG"
fi

echo "Done: GitHub release $TAG updated with ${#FOUND[@]} asset(s)."

