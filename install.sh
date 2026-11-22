#!/bin/bash
# Build Hone from source and install it to /Applications.
# Usage: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install Xcode or run: xcode-select --install" >&2
  exit 1
fi

# Quit a running copy so the bundle can be replaced.
osascript -e 'tell application id "com.dvd90.PromptForge" to quit' >/dev/null 2>&1 || true
sleep 1
# The quit Apple Event can be refused (Automation permission); without this, the old copy keeps running.
pkill -x PromptForge 2>/dev/null || true

./build.sh --install

# Register the right-click Services entries.
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

open "/Applications/Hone.app"
echo
echo "✅ Hone installed and launched."
echo "   • Settings (⌘,) → Provider: pick Claude Code, Codex, Gemini CLI or an API key."
echo "   • Select text anywhere and press ⌃⌥Space."
echo "   • Allow it under System Settings → Privacy & Security → Accessibility to use Replace."
