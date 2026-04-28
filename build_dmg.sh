#!/usr/bin/env bash
# build_dmg.sh — Build AskBar in Release and package it as a DMG.
# Uses only macOS built-ins (xcodebuild + hdiutil). No Homebrew needed.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="AskBar"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="AskBar.app"
DMG_NAME="AskBar.dmg"
VOL_NAME="AskBar"
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
  build | tail -20

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIG/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
  echo "✖ Build failed: $APP_PATH not found"
  exit 1
fi

echo "▶︎ Ad-hoc signing the app…"
codesign --force --deep --sign - "$APP_PATH"

echo "▶︎ Copying .app to staging…"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▶︎ Creating DMG…"
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$BUILD_DIR/$DMG_NAME" >/dev/null

echo "✅ DMG created: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"

echo ""
echo "ℹ︎ This DMG is ad-hoc signed (not notarized). On first launch users must:"
echo "    Right-click AskBar.app → Open  (or run: xattr -dr com.apple.quarantine /Applications/AskBar.app)"
