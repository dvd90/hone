#!/bin/bash
# Builds a drag-to-install DMG: build/Hone-<version>.dmg
# With a Developer ID certificate the DMG is also signed, notarized and stapled. One-time setup:
#   xcrun notarytool store-credentials hone-notary --apple-id <apple-id> --team-id <team-id>
# (prompts for an app-specific password; use NOTARY_PROFILE=<name> for another profile name)
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

SIGN_ID=$(codesign -dvv "build/Hone.app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')
if [ -z "$SIGN_ID" ]; then
  echo "Built: $DMG (ad-hoc signed, NOT notarized: no Developer ID Application certificate found)"
  exit 0
fi
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-hone-notary}" --wait
xcrun stapler staple "$DMG"   # fails if notarization was rejected: see `xcrun notarytool log <id>`
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built: $DMG (Developer ID signed, notarized, stapled)"
