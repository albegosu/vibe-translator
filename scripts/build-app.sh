#!/usr/bin/env bash
# Builds VibeTranslator.app into ./build.
#
#   scripts/build-app.sh            # release build, ad-hoc signature
#   CONFIG=debug scripts/build-app.sh
#   CODESIGN_IDENTITY="VibeTranslator Dev" scripts/build-app.sh
#
# macOS ties the Accessibility permission to the code signature. With an ad-hoc
# signature every rebuild looks like a new app and the permission has to be granted
# again; signing with a stable identity (see README) avoids that.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/VibeTranslator.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VibeTranslator" "$APP/Contents/MacOS/VibeTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signature: ${IDENTITY/#-/ad-hoc})"
