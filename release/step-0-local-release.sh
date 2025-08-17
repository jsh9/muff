#!/bin/bash
set -euo pipefail

# Main release script - orchestrates the entire release process
# Usage: ./scripts/local-release.sh <version-tag> [--skip-build] [--skip-pypi] [--skip-github]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
    echo "Usage: $0 <version-tag> [options]"
    echo ""
    echo "Options:"
    echo "  --skip-build     Skip the build step (use existing artifacts)"
    echo "  --skip-pypi      Skip PyPI publishing"
    echo "  --skip-github    Skip GitHub release creation"
    echo ""
    echo "Example:"
    echo "  $0 v1.0.0                    # Full release"
    echo "  $0 v1.0.0 --skip-build      # Use existing build artifacts"
    echo "  $0 v1.0.0 --skip-pypi       # Only create GitHub release"
}

if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
fi

VERSION_TAG="$1"
shift

# Parse options
SKIP_BUILD=false
SKIP_PYPI=false
SKIP_GITHUB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-pypi)
            SKIP_PYPI=true
            shift
            ;;
        --skip-github)
            SKIP_GITHUB=true
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo "🚀 Starting release process for $VERSION_TAG"
echo "📋 Configuration:"
echo "   - Skip build: $SKIP_BUILD"
echo "   - Skip PyPI: $SKIP_PYPI"
echo "   - Skip GitHub: $SKIP_GITHUB"
echo ""

# Validate version tag format
if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "❌ Invalid version tag format. Expected: vX.Y.Z or vX.Y.Z-suffix"
    echo "   Examples: v1.0.0, v1.2.3-beta.1"
    exit 1
fi

# Check git status
if [[ -n $(git status --porcelain) ]]; then
    echo "❌ Working directory is not clean. Please commit or stash changes."
    git status --short
    exit 1
fi

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "⚠️  You are not on the main branch (currently on: $CURRENT_BRANCH)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted"
        exit 1
    fi
fi

# Step 1: Build
if [[ "$SKIP_BUILD" == "false" ]]; then
    echo "🔨 Step 1/3: Building artifacts..."
    echo "Choose build target:"
    echo "  1) macOS only"
    echo "  2) Linux only (cross-compilation)"
    echo "  3) Windows only (cross-compilation)"
    echo "  4) All platforms"
    read -p "Enter choice (1-4) [default: 1]: " -n 1 -r
    echo

    case ${REPLY:-1} in
        1)
            "$SCRIPT_DIR/step-1-build-macos.sh"
            ;;
        2)
            "$SCRIPT_DIR/step-1-build-linux.sh"
            ;;
        3)
            "$SCRIPT_DIR/step-1-build-windows.sh"
            ;;
        4)
            "$SCRIPT_DIR/step-1-build-macos.sh"
            "$SCRIPT_DIR/step-1-build-linux.sh"
            "$SCRIPT_DIR/step-1-build-windows.sh"
            ;;
        *)
            echo "Invalid choice, defaulting to macOS"
            "$SCRIPT_DIR/step-1-build-macos.sh"
            ;;
    esac
    echo "✅ Build completed"
    echo ""
else
    echo "⏭️  Step 1/3: Skipping build"
    # Verify artifacts exist
    if [[ ! -d "dist" ]] || ! ls dist/*.whl 1> /dev/null 2>&1; then
        echo "❌ No build artifacts found. Cannot skip build."
        exit 1
    fi
    echo ""
fi

# Step 2: Create GitHub Release
if [[ "$SKIP_GITHUB" == "false" ]]; then
    echo "📦 Step 2/3: Creating GitHub release..."
    "$SCRIPT_DIR/step-2-create-release.sh" "$VERSION_TAG"
    echo "✅ GitHub release created"
    echo ""
else
    echo "⏭️  Step 2/3: Skipping GitHub release"
    echo ""
fi

# Step 3: Publish to PyPI
if [[ "$SKIP_PYPI" == "false" ]]; then
    echo "🐍 Step 3/3: Publishing to PyPI..."

    # Check if this is a prerelease
    if [[ "$VERSION_TAG" =~ -.*$ ]]; then
        echo "⚠️  This appears to be a prerelease version: $VERSION_TAG"
        read -p "Do you want to publish prereleases to PyPI? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "⏭️  Skipping PyPI publication for prerelease"
        else
            "$SCRIPT_DIR/step-3-publish-pypi.sh"
            echo "✅ Published to PyPI"
        fi
    else
        "$SCRIPT_DIR/step-3-publish-pypi.sh"
        echo "✅ Published to PyPI"
    fi
    echo ""
else
    echo "⏭️  Step 3/3: Skipping PyPI publication"
    echo ""
fi

echo "🎉 Release process completed for $VERSION_TAG!"
echo ""
echo "📋 Summary:"
echo "   - Version: $VERSION_TAG"
echo "   - Build: $([ "$SKIP_BUILD" == "false" ] && echo "✅ Completed" || echo "⏭️ Skipped")"
echo "   - GitHub: $([ "$SKIP_GITHUB" == "false" ] && echo "✅ Completed" || echo "⏭️ Skipped")"
echo "   - PyPI: $([ "$SKIP_PYPI" == "false" ] && echo "✅ Completed" || echo "⏭️ Skipped")"
echo ""
echo "🔗 Next steps:"
if [[ "$SKIP_GITHUB" == "false" ]]; then
    echo "   - View release: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\([^/]*\/[^/]*\).*/\1/' | sed 's/\.git$//')/releases/tag/$VERSION_TAG"
fi
if [[ "$SKIP_PYPI" == "false" ]]; then
    echo "   - View on PyPI: https://pypi.org/project/muff/"
    echo "   - Install: pip install muff"
fi