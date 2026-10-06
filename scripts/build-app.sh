#!/usr/bin/env bash
# Builds VibeTranslator.app into ./build.
#
#   scripts/build-app.sh            # release build, ad-hoc signature
#   CONFIG=debug scripts/build-app.sh
#   CODESIGN_IDENTITY="VibeTranslator Dev" scripts/build-app.sh
#   VERSION=0.2.0 BUILD_NUMBER=42 ARCHS="arm64 x86_64" scripts/build-app.sh   # what CI releases use
#
# macOS ties the Accessibility permission to the code signature. With an ad-hoc
# signature every rebuild looks like a new app and the permission has to be granted
# again; signing with a stable identity (see README) avoids that.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/VibeTranslator.app"

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do
    ARCH_FLAGS+=(--arch "$arch")
done

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VibeTranslator" "$APP/Contents/MacOS/VibeTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signature: ${IDENTITY/#-/ad-hoc})"
