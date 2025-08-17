#!/bin/bash
set -euo pipefail

# Local PyPI publishing script
# Based on .github/workflows/publish-pypi.yml

echo "📦 Publishing to PyPI..."

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "📥 Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source ~/.cargo/env
fi

# Check if wheels directory exists
if [[ ! -d "dist" ]]; then
    echo "❌ No dist/ directory found. Run local-build.sh first."
    exit 1
fi

# Check if there are any wheels
if ! ls dist/*.whl 1> /dev/null 2>&1; then
    echo "❌ No wheel files found in dist/. Run local-build.sh first."
    exit 1
fi

echo "🔍 Found wheels:"
ls -la dist/*.whl

# Publish to PyPI using uv
echo "🚀 Publishing to PyPI..."
uv publish -v dist/*

echo "✅ Successfully published to PyPI!"
echo "🌐 Check your package at: https://pypi.org/project/muff/"