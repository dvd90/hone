#!/bin/bash
# Build Prompt Forge from source and install it to /Applications.
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

./build.sh --install

# Register the right-click Services entries.
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

open "/Applications/Prompt Forge.app"
echo
echo "✅ Prompt Forge installed and launched."
echo "   • Settings (⌘,) → Provider: pick Claude Code, Codex, Gemini CLI or an API key."
echo "   • Select text anywhere and press ⌃⌥Space."
echo "   • Allow it under System Settings → Privacy & Security → Accessibility to use Replace."
