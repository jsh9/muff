#!/bin/bash
set -euo pipefail

# GitHub release creation script
# Based on .github/workflows/release.yml

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version-tag>"
    echo "Example: $0 v1.0.0"
    exit 1
fi

VERSION_TAG="$1"

echo "🚀 Creating GitHub release: $VERSION_TAG"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is required but not installed"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
fi

# Check if user is authenticated with GitHub
if ! gh auth status > /dev/null 2>&1; then
    echo "❌ Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

# Check if binary archive exists
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    TARGET="aarch64-apple-darwin"
elif [[ "$ARCH" == "x86_64" ]]; then
    TARGET="x86_64-apple-darwin"
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

ARCHIVE_FILE="muff-$TARGET.tar.gz"
CHECKSUM_FILE="$ARCHIVE_FILE.sha256"

if [[ ! -f "$ARCHIVE_FILE" ]]; then
    echo "❌ Binary archive not found: $ARCHIVE_FILE"
    echo "Run local-build.sh first."
    exit 1
fi

if [[ ! -f "$CHECKSUM_FILE" ]]; then
    echo "❌ Checksum file not found: $CHECKSUM_FILE"
    echo "Run local-build.sh first."
    exit 1
fi

# Check if wheels exist
if [[ ! -d "dist" ]] || ! ls dist/*.whl 1> /dev/null 2>&1; then
    echo "❌ No wheels found in dist/. Run local-build.sh first."
    exit 1
fi

# Get current commit
RELEASE_COMMIT=$(git rev-parse HEAD)

# Check if tag already exists
if git tag -l | grep -q "^$VERSION_TAG$"; then
    echo "⚠️  Tag $VERSION_TAG already exists locally"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "$VERSION_TAG"
        git push origin ":refs/tags/$VERSION_TAG" 2>/dev/null || true
    else
        echo "❌ Aborted"
        exit 1
    fi
fi

# Create and push tag
echo "🏷️  Creating and pushing tag: $VERSION_TAG"
git tag "$VERSION_TAG" "$RELEASE_COMMIT"
git push origin "$VERSION_TAG"

# Generate release notes
RELEASE_TITLE="muff $VERSION_TAG"
RELEASE_BODY="## What's Changed

This release includes:
- Binary distributions for macOS ($TARGET)
- Python wheels for PyPI distribution
- Source distribution

## Installation

### From PyPI
\`\`\`bash
pip install muff
\`\`\`

### From GitHub Release
\`\`\`bash
# Download and extract the binary
curl -LO https://github.com/$(gh repo view --json owner,name -q '.owner.login + \"/\" + .name')/releases/download/$VERSION_TAG/$ARCHIVE_FILE
tar -xzf $ARCHIVE_FILE
# Move to PATH
sudo mv muff-$TARGET/muff /usr/local/bin/
\`\`\`

## Checksums

\`\`\`
$(cat "$CHECKSUM_FILE")
\`\`\`

**Full Changelog**: https://github.com/$(gh repo view --json owner,name -q '.owner.login + \"/\" + .name')/compare/$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "Initial")...$VERSION_TAG"

# Write release notes to temporary file
NOTES_FILE=$(mktemp)
echo "$RELEASE_BODY" > "$NOTES_FILE"

# Create the GitHub release with artifacts
echo "📦 Creating GitHub release with artifacts..."
gh release create "$VERSION_TAG" \
    --target "$RELEASE_COMMIT" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" \
    "$ARCHIVE_FILE" \
    "$CHECKSUM_FILE" \
    dist/*.whl \
    dist/*.tar.gz

# Clean up
rm "$NOTES_FILE"

echo "✅ GitHub release created successfully!"
echo "🌐 View at: $(gh repo view --web --json url -q '.url')/releases/tag/$VERSION_TAG"