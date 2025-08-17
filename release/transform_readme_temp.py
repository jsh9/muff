"""Create a temporary README.md for PyPI without modifying the original.

This script creates a simplified README.md for PyPI that removes the fancy 
light/dark theme image switching and just uses a simple image.
"""

from __future__ import annotations

import argparse
from pathlib import Path

URL = "https://user-images.githubusercontent.com/1309177/{}.svg"
URL_LIGHT = URL.format("232603516-4fb4892d-585c-4b20-b810-3db9161831e4")
URL_DARK = URL.format("232603514-c95e9b0f-6b31-43de-9a80-9e844173fd6a")

# GitHub format (complex with light/dark theme)
GITHUB = f"""<p align="center">
  <picture align="center">
    <source media="(prefers-color-scheme: dark)" srcset="{URL_DARK}">
    <source media="(prefers-color-scheme: light)" srcset="{URL_LIGHT}">
    <img alt="Shows a bar chart with benchmark results." src="{URL_LIGHT}">
  </picture>
</p>"""

# Simple format for PyPI (just one image)
PYPI = f"""<p align="center">
  <img alt="Shows a bar chart with benchmark results." src="{URL_LIGHT}">
</p>"""


def create_pypi_readme() -> None:
    """Create a temporary README.md for PyPI without modifying the original."""
    # Read original README.md
    with Path("README.md").open(encoding="utf8") as fp:
        content = fp.read()
    
    # Create simplified version for PyPI
    pypi_content = content.replace(GITHUB, PYPI)
    
    # Backup original and replace with PyPI version temporarily
    # This allows maturin to pick up the simplified version
    Path("README.md").rename("README.md.original")
    with Path("README.md").open("w", encoding="utf8") as fp:
        fp.write(pypi_content)
    
    print("Created temporary simplified README.md for PyPI packaging")


def restore_original() -> None:
    """Restore original README file."""
    original_readme = Path("README.md.original")
    if original_readme.exists():
        # Remove temporary README and restore original
        Path("README.md").unlink()
        original_readme.rename("README.md")
        print("Restored original README.md")
    else:
        print("No backup README.md.original found")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create temporary README.md for PyPI packaging.",
    )
    parser.add_argument(
        "--action",
        type=str,
        required=True,
        choices=("create", "cleanup"),
        help="create: make temporary README, cleanup: remove temporary files"
    )
    args = parser.parse_args()
    
    if args.action == "create":
        create_pypi_readme()
    elif args.action == "cleanup":
        restore_original()