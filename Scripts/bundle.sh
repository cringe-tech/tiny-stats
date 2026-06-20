#!/bin/bash
# Builds TinyStats.app from the SwiftPM executable. No Xcode required.
# Usage: Scripts/bundle.sh [--debug]
set -euo pipefail

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then CONFIG="debug"; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="TinyStats.app"
CONTENTS="$APP/Contents"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product TinyStats

BIN_DIR="$(swift build -c "$CONFIG" --product TinyStats --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/TinyStats" "$CONTENTS/MacOS/TinyStats"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Optional version/build override (used by the release pipeline, derived from the git tag).
# Locally these are unset, so the values committed in Info.plist are kept.
if [[ -n "${TINYSTATS_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$TINYSTATS_VERSION" "$CONTENTS/Info.plist"
fi
# Local debug builds: stamp a YYMMDD.HHMMSS build number so you can tell at a glance
# (Settings → "Build …") which build is actually running.
if [[ "$CONFIG" == "debug" && -z "${TINYSTATS_BUILD:-}" ]]; then
    TINYSTATS_BUILD="$(date +%y%m%d.%H%M%S)"
fi
if [[ -n "${TINYSTATS_BUILD:-}" ]]; then
    plutil -replace CFBundleVersion -string "$TINYSTATS_BUILD" "$CONTENTS/Info.plist"
fi

# SwiftPM resource images (donate buttons, logo) → Contents/Resources, where Bundle.main
# finds them at runtime (see SettingsView.resourceImage). Kept out of the SwiftPM .bundle on
# purpose: that bundle's generated accessor expects a path that doesn't exist in a hand-
# assembled .app and would fatalError.
if [ -d "$BIN_DIR/TinyStats_TinyStats.bundle" ]; then
    cp "$BIN_DIR/TinyStats_TinyStats.bundle/"*.png "$CONTENTS/Resources/" 2>/dev/null || true
fi

# Ad-hoc signature so the app launches without a Developer ID and TCC stays happy.
echo "==> ad-hoc codesign"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "   (codesign skipped/failed — app still runnable locally)"

echo "==> done: $ROOT/$APP"
