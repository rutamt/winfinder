#!/usr/bin/env bash
# Builds WinFinder in release mode and wraps it in a minimal WinFinder.app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WinFinder"
BUNDLE_ID="${BUNDLE_ID:-com.winfinder.WinFinder}"
VERSION="${VERSION:-1.0.0}"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>WinFinder controls Finder to find the current folder, and to select and rename new text documents it creates.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Code signing"
# Use a stable identity if you have one (export SIGN_IDENTITY="Apple Development: ..."), so
# Accessibility/Automation grants survive rebuilds. Ad-hoc ("-") works but macOS may ask again
# after each rebuild.
codesign --force --deep --sign "${SIGN_IDENTITY:--}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"

echo
echo "Done: $APP"
echo "Run with:  open \"$APP\""
echo "Install:   cp -R \"$APP\" /Applications/"
