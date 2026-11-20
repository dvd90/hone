#!/bin/bash
# Builds a drag-to-install DMG: build/Hone-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
./build.sh

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "build/Hone.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-readme.txt "$STAGE/READ ME FIRST.txt"

DMG="build/Hone-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Hone $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built: $DMG"
