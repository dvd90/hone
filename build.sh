#!/bin/bash
# Builds Hone.app. Usage: ./build.sh [--install]
# Signs with your Developer ID Application certificate when one is installed (notarizable, and
# Accessibility permission survives rebuilds); otherwise ad-hoc. Override with SIGN_ID="…" or SIGN_ID=-.
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
# Accent color asset (needs full Xcode for actool; without it the app falls back to the system accent).
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --output-partial-info-plist "$(mktemp)" >/dev/null
fi
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)}"
SIGN_ID="${SIGN_ID:--}"
if [ "$SIGN_ID" = "-" ]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
# Hardened runtime is required for notarization; the app needs no entitlements.
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_ID" "$APP"
echo "Built: $APP (signed: $([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Hone.app"
  rm -rf "/Applications/Prompt Forge.app"   # same bundle ID under the old name
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Hone.app"
fi
