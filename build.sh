#!/bin/bash
# Builds Hone.app. Usage: ./build.sh [--install]
# Signs with your Developer ID Application certificate when one is installed (notarizable). A local
# --install falls back to an Apple Development certificate. With either, the Accessibility grant survives
# rebuilds; otherwise the build is ad-hoc. Override with SIGN_ID="…" or SIGN_ID=-.
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
IDS="$(security find-identity -v -p codesigning)"
cert() { sed -n "s/.*\"\($1: .*\)\"\$/\1/p" <<<"$IDS" | head -1; }
SIGN_ID="${SIGN_ID:-$(cert "Developer ID Application")}"
# Local installs only, so a release DMG is never shipped with a development certificate.
if [ "${1:-}" = "--install" ]; then SIGN_ID="${SIGN_ID:-$(cert "Apple Development")}"; fi
SIGN_ID="${SIGN_ID:--}"
case "$SIGN_ID" in "Developer ID"*) TIMESTAMP="--timestamp" ;; *) TIMESTAMP="--timestamp=none" ;; esac
# Hardened runtime is required for notarization; the app needs no entitlements.
codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_ID" "$APP"
echo "Built: $APP (signed: $([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Hone.app"
  rm -rf "/Applications/Prompt Forge.app"   # same bundle ID under the old name
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Hone.app"
fi
