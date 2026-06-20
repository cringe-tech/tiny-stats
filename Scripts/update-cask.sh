#!/bin/bash
# Stamps a version + sha256 into the Homebrew cask. Used by the release workflow and
# runnable by hand. Usage: Scripts/update-cask.sh <version> <sha256> [cask-path]
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version> <sha256> [cask-path]}"
SHA="${2:?usage: update-cask.sh <version> <sha256> [cask-path]}"
CASK="${3:-Casks/tinystats.rb}"

sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"

echo "updated $CASK -> version $VERSION, sha256 $SHA"
