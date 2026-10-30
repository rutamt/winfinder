#!/usr/bin/env bash
# Builds WinFinder.app (via bundle.sh) and packages it into a drag-to-install DMG.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WinFinder"
VERSION="${VERSION:-1.0.0}"
export VERSION
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$OUT_DIR/dmg-staging"

./bundle.sh

echo "==> Creating $DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo
echo "Done: $DMG"
