#!/usr/bin/env bash
# build_dmg.sh — Build AskBar in Release and package as a DMG.
# Requires: Xcode command line tools, and `create-dmg` (brew install create-dmg).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="AskBar"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="AskBar.app"
DMG_NAME="AskBar.dmg"
STAGING="$BUILD_DIR/dmg-staging"

echo "▶︎ Cleaning build dir…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$STAGING"

echo "▶︎ Building $SCHEME ($CONFIG)…"
xcodebuild \
  -project "$PROJECT_DIR/AskBar.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIG/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
  echo "✖ Build failed: $APP_PATH not found"
  exit 1
fi

echo "▶︎ Copying .app to staging…"
cp -R "$APP_PATH" "$STAGING/"

echo "▶︎ Creating DMG…"
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "✖ create-dmg not installed. Run: brew install create-dmg"
  exit 1
fi

rm -f "$BUILD_DIR/$DMG_NAME"

create-dmg \
  --volname "AskBar" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "$APP_NAME" 160 190 \
  --app-drop-link 380 190 \
  --no-internet-enable \
  "$BUILD_DIR/$DMG_NAME" \
  "$STAGING/"

echo "✅ DMG created: $BUILD_DIR/$DMG_NAME"
echo ""
echo "🔐 Codesigning notes:"
echo "  If you have a Developer ID Application certificate:"
echo "    codesign --deep --force --options runtime --sign 'Developer ID Application: YOUR NAME (TEAMID)' '$STAGING/$APP_NAME'"
echo "  And to notarize:"
echo "    xcrun notarytool submit '$BUILD_DIR/$DMG_NAME' --keychain-profile 'AC_PROFILE' --wait"
echo "    xcrun stapler staple '$BUILD_DIR/$DMG_NAME'"
