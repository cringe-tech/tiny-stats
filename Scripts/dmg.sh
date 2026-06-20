#!/bin/bash
# Builds a distributable TinyStats.dmg (drag-to-Applications) from the .app bundle.
# The asset name is intentionally unversioned so a stable download link works:
#   https://github.com/<owner>/<repo>/releases/latest/download/TinyStats.dmg
# Usage: Scripts/dmg.sh    (honours TINYSTATS_VERSION / TINYSTATS_BUILD for the bundle)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build the (ad-hoc signed) app bundle first.
"$ROOT/Scripts/bundle.sh"

APP="TinyStats.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
OUT_DIR="dist"
DMG="$OUT_DIR/TinyStats.dmg"

mkdir -p "$OUT_DIR"
rm -f "$DMG"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> hdiutil create $DMG (v$VERSION)"
hdiutil create -volname "TinyStats" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "==> done: $ROOT/$DMG"
echo "    version: $VERSION"
echo "    sha256:  $SHA"
