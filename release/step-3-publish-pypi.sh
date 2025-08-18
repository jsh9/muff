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

# Publish to PyPI using uv with trusted publisher
echo "🚀 Publishing to PyPI..."
echo "⚠️  This script requires Trusted Publisher authentication."
echo "For local publishing, you need to set PYPI_API_TOKEN environment variable."
echo "Or run this from GitHub Actions where Trusted Publisher is configured."

if [[ -n "${PYPI_API_TOKEN:-}" ]]; then
    echo "Using API token for authentication..."
    uv publish -v --token "$PYPI_API_TOKEN" dist/*
else
    echo "❌ No PYPI_API_TOKEN found in environment."
    echo "Either:"
    echo "1. Set PYPI_API_TOKEN environment variable with your PyPI API token"
    echo "2. Run this from GitHub Actions where Trusted Publisher is configured"
    echo ""
    echo "To create an API token:"
    echo "1. Go to https://pypi.org/manage/account/token/"
    echo "2. Create a new token with scope limited to this project"
    echo "3. Export it: export PYPI_API_TOKEN=your-token-here"
    exit 1
fi

echo "✅ Successfully published to PyPI!"
echo "🌐 Check your package at: https://pypi.org/project/muff/"