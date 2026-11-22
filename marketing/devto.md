---
title: Turning one-line prompts into specific ones from any Mac app
published: false
tags: macos, swift, opensource, ai
---

Most of my prompts to coding agents started as one line: "add tests for the payment service". The agent then had to guess the stack, the test framework and what done means. I built Hone to fix that without leaving the app I'm working in.

Hone is an open-source, native macOS app. You select text anywhere, press ⌃⌥Space, and run an action on it. The main action, Improve Prompt, rewrites a draft prompt for a target model, scores it before and after, and lists the assumptions it made. Other actions handle everyday text, such as Proofread and Summarize, and you can add your own.

## Walkthrough: a better prompt for a coding agent

### 1. Install and connect a provider

Hone needs macOS 14 or later and Xcode or the Command Line Tools:

```bash
git clone https://github.com/dvd90/prompt-forge.git
cd prompt-forge
./install.sh
```

The default provider is Claude Code. If `claude` is installed and logged in, there's nothing to configure. Codex CLI, Gemini CLI, an Anthropic API key and OpenAI-compatible endpoints such as Ollama also work.

Grant Accessibility in System Settings → Privacy & Security → Accessibility, so the hotkey can read your selection and paste the result back.

### 2. Save a profile

In Settings → Context, add a profile that describes your project. For example:

> Backend service in TypeScript and Node.js with PostgreSQL. Tests use Vitest and run in GitHub Actions. We prefer small pull requests.

The selected profile goes with every Improve Prompt run, from the main window and from the hotkey. In the main window, set Target to "Coding agent". The quick panel uses the same Target and Depth.

### 3. Select the draft and press the hotkey

Select "add tests for the payment service" in your editor and press ⌃⌥Space. The panel opens near the cursor without taking focus. Its "Prompt context" row shows the profile and a chip with the app and window title you came from. Remove the chip if you don't want the window title sent.

Press 1 for Improve Prompt.

### 4. Read the result

The rewritten prompt streams in. Instead of leaving `{{PLACEHOLDERS}}`, Hone writes reasonable assumptions into the prompt and shows them in a short "Assumed: …" line. When the target is a coding agent, Hone asks the model to have the agent check facts it can find in the repository instead of assuming them. Press Return to replace your selection, or click Open in App.

In the main window you get:
- a score from 0 to 100 for the draft and for the improved prompt
- a diagnosis of what was weak and a list of changes
- every assumption, each with a field to correct it, and a "Re-run with corrections" button
- a Refine box for feedback such as "shorter" or "return JSON"

## How it runs

With a subscription, Hone runs the official CLI headless, so requests use your existing login. Claude Code is called with tools, MCP servers, slash commands, your settings and session files turned off, so your personal setup doesn't leak into results. Codex runs in a read-only sandbox and Gemini in plan mode. API keys stay in the macOS Keychain. There is no backend and no telemetry.

Selected text and context are delimited and treated as content, never as instructions.

## Try it, or help

Hone is MIT licensed and written in SwiftUI with no third-party dependencies: https://github.com/dvd90/prompt-forge

The Gemini CLI provider hasn't been tested end to end yet, and reports from apps where the hotkey or Replace misbehaves are especially useful. Issues and pull requests are welcome.
