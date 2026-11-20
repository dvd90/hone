#!/bin/bash
# Builds Hone.app (ad-hoc signed). Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary (Apple silicon + Intel).
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PromptForge"
APP="build/Hone.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PromptForge"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Hone.app"
  rm -rf "/Applications/Prompt Forge.app"   # same bundle ID under the old name
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Hone.app"
fi
