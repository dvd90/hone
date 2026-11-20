#!/bin/bash
# Builds Prompt Forge.app (ad-hoc signed). Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary (Apple silicon + Intel).
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PromptForge"
APP="build/Prompt Forge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PromptForge"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Prompt Forge.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Prompt Forge.app"
fi
