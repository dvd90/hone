# Hone ✨

[![CI](https://github.com/dvd90/hone/actions/workflows/ci.yml/badge.svg)](https://github.com/dvd90/hone/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A native macOS app that turns rough prompts into great ones and runs AI text actions on any text you select, using the AI subscription you already pay for.**

[![Hone demo: select text, press Ctrl + Option + Space, improve the prompt](docs/demo.gif)](docs/demo.mp4)

- 🪄 **Improve Prompt**: rewrites your prompt with proven prompt-engineering techniques, grounded in your context (a saved profile, notes, attached files, the app you were in, notes from your Obsidian vault). It scores the prompt before and after, explains what was wrong, and lists the assumptions it made so you can correct them.
- ✍️ **Text actions**: Rewrite, Proofread, Make Concise, Professional, Friendly, Summarize, Explain, Translate, Draft Reply, plus **your own custom actions**.
- ⌨️ **Works everywhere**: select text in any app, press **⌃⌥Space**, pick an action, then **Replace** it in place or **Copy** it.
- 🔌 **Bring your own AI**: Claude, ChatGPT or Gemini **subscriptions** through their official CLIs, or an Anthropic / OpenAI-compatible **API key** (OpenAI, OpenRouter, Ollama, LM Studio…).
- 🔒 **Private by design**: no backend, no telemetry. Keys live in the macOS Keychain, and text goes only to the provider you choose.

Hone is open source under the [MIT License](LICENSE) at [github.com/dvd90/hone](https://github.com/dvd90/hone), and improvements are welcome: bug reports, ideas, new actions, new providers, tests and fixes. See [Contributing](#contributing).

---

## Contents
- [Install](#install)
- [First-run setup](#first-run-setup)
- [How to use](#how-to-use)
- [Providers](#providers)
- [Actions](#actions)
- [How Improve Prompt works](#how-improve-prompt-works)
- [Architecture](#architecture)
- [Design](#design)
- [Extending](#extending)
- [Building & testing](#building--testing)
- [Troubleshooting](#troubleshooting)
- [Privacy & security](#privacy--security)
- [Contributing](#contributing)
- [License](#license)

---

## Install

**Requirements:** macOS 14 Sonoma or later (Apple silicon or Intel).

### Option A: DMG installer (recommended)
1. Download `Hone-<version>.dmg` from the repo's **[Releases](../../releases)** page.
2. Open it and drag **Hone** into **Applications**.
3. Open it. A notarized release (Developer ID signed) opens after the usual confirmation. An ad-hoc-signed build, including 1.0.0 (released as Prompt Forge), is blocked on first launch; clear it once:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Hone.app"
   ```
   or open it once, then click **Open Anyway** in **System Settings → Privacy & Security**.

The current release, 1.0.0, is `PromptForge-1.0.0.dmg`. It predates the Hone name, Context and Assumptions; build from source (Option B) to get them.

### Option B: build from source
Requires Xcode or the Xcode Command Line Tools (Swift 5.10+). Full Xcode also compiles the accent-color asset; with only the Command Line Tools the app uses your system accent color.
```bash
git clone https://github.com/dvd90/hone.git
cd hone
./install.sh                        # builds, installs to /Applications, launches
```

---

## First-run setup

1. **Pick a provider**: open **Settings (⌘,) → Provider**. The default is **Claude Code**, so if `claude` is installed and logged in, there's nothing to do. Click **Test connection** to confirm.
2. **Grant Accessibility** (optional, recommended): **System Settings → Privacy & Security → Accessibility → Hone**. This lets the hotkey read your selection and paste results back. Without it, the hotkey works on your **clipboard** instead and Replace is hidden.
3. **Choose a hotkey**: **Settings → Shortcut**: ⌃⌥Space (default), ⌥Space, ⇧⌘Space, ⌃⌥P or disabled.

---

## How to use

### 1. Quick actions in any app
```
select text  →  ⌃⌥Space  →  press 1–9 (or click)  →  ⏎ Replace   or   ⇧⌘C Copy
```
- A floating panel appears near your cursor without stealing focus from the app you're in.
- **Replace** pastes the result over your original selection.
- **Open in App** moves the result into the main window so you can refine it.
- **Esc** closes the panel; **⌘←** goes back to the action list.

### 2. The main window
| Shortcut | What it does |
|---|---|
| ⌘↩ | Run the selected action |
| ⌘. | Stop |
| ⇧⌘C | Copy the result |
| ⌘N | New |
| ⇧⌘K | Quick actions on the clipboard |
| ⌘, | Settings |

For **Improve Prompt** you also get:
- **Score**: the draft's score and the improved prompt's score (0–100) on one gradient track, with the improved prompt and **Copy** right below it.
- **Target**: Claude, GPT, Gemini, Any LLM, Coding agent (Claude Code / Cursor) or Image model. The rewrite follows each target's conventions.
- **Depth**: *Light* (minimal edits), *Standard*, or *Production* (a reusable system prompt with `{{VARIABLES}}`).
- **Techniques**: leave on *auto*, or force specific ones: Role, Context & why, Success criteria, Structure / tags, Examples, Step-by-step, Output format, Edge cases, Variables.
- **Context**: what makes the prompt specific instead of generic.
  - **Profile**: reusable notes about you or a project (stack, audience, conventions), saved in **Settings → Context** and picked per run. The selected profile also applies to the quick panel.
  - **Notes**: anything specific to this run.
  - **Files**: attach text files with the paperclip or by dropping them on the options (UTF-8 text, up to 50 KB each and 100 KB in total).
  - **Where you came from**: with the hotkey, Hone adds the app and window title you were in (for example "Xcode — AppState.swift") as a chip you can remove before running.
  - **Obsidian**: choose a vault in **Settings → Context** and Improve Prompt adds notes when they help: notes you link with `[[Note]]` in a profile, your notes or the draft; the note open in Obsidian when you press the hotkey there; and up to 3 notes that match the draft (a slider sets how close the match must be). Hone reads the Markdown files directly, so there is no plugin to install. Each note shows as a chip you can remove, files in Obsidian's *Excluded files* are never sent, and History keeps which notes a run used, not their text.
- **Assumptions**: when something is missing, the prompt states a reasonable assumption instead of leaving `{{PLACEHOLDERS}}`. Each one is listed under the result; correct any and click **Re-run with corrections**. (Production depth still uses `{{VARIABLES}}` for inputs that change between uses.)
- **Refine**: free-text feedback ("shorter", "return JSON") that keeps the conversation going.

Every run is saved to **History** in the sidebar. Click an entry to reopen it and keep refining; right-click to copy or delete.

### 3. Right-click Services
Select text → right-click → **Services → Hone: Improve Prompt** or **Hone: Quick Actions**.
You can bind these to keys in **System Settings → Keyboard → Keyboard Shortcuts → Services**.

### 4. Menu bar
The ✨ wand icon gives you quick actions on the selection or clipboard, opens the window, and shows the active provider. The app keeps running in the menu bar after you close the window, so the hotkey always works.

---

## Providers

| Provider | Auth | Streaming | Setup |
|---|---|---|---|
| **Claude Code** *(default)* | Claude Pro / Max subscription | ✅ | Install [Claude Code](https://docs.claude.com/en/docs/claude-code) and run `claude` once to log in |
| **Codex CLI** | ChatGPT subscription | ❌ (result arrives at once) | Install Codex and run `codex login` |
| **Gemini CLI** | Google account | ✅ | Install Gemini CLI and run `gemini` once, choosing "Login with Google" |
| **Anthropic API** | API key | ✅ | Paste a key from console.anthropic.com and pick a model |
| **OpenAI-compatible** | API key (optional for local) | ✅ | Preset buttons for OpenAI, OpenRouter, Ollama and LM Studio; enter a model ID |

**How subscription mode works:** Hone runs the official CLI in headless mode, so requests use your existing login and count against your plan. No tokens are copied or stored. Calls are isolated:

- **Claude Code:** `claude -p --system-prompt … --tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence`. No tools, no hooks, no MCP servers, no CLAUDE.md and no session files, so your personal Claude Code setup can't leak into results.
- **Codex:** `codex exec --ephemeral -s read-only --skip-git-repo-check`.
- **Gemini:** `gemini -p --approval-mode plan` (read-only).

All CLIs run in an empty temp folder. GUI apps don't inherit your shell `PATH`, so Hone reads it once from a login shell. Settings shows where each CLI was found.

You can set a model for each provider; leave it blank to use the CLI's default (for Claude Code: `sonnet`, `opus`, `haiku` or a full model ID).

---

## Actions

| # | Action | What it does |
|---|---|---|
| 1 | **Improve Prompt** | Structured prompt-engineering report (see below) |
| 2 | Rewrite | Clearer, better structured, same voice and length |
| 3 | Proofread | Spelling, grammar and punctuation only |
| 4 | Make Concise | Cuts filler and keeps every point |
| 5 | Professional | Confident, clear work tone |
| 6 | Friendly | Warm, natural tone |
| 7 | Summarize | Short bullet list, most important point first |
| 8 | Explain | Plain-language explanation |
| 9 | To English | Idiomatic translation that keeps formatting |
| – | Draft Reply | Replies to a message as you, with `{{placeholders}}` for unknowns |

**Custom actions:** **Settings → Actions → Add custom action**. Give it a name, an icon and an instruction, e.g. *"Turn this into a LinkedIn post with a strong hook, max 120 words."* It appears in the main window and the quick panel straight away. You can hide any built-in action with its toggle. The first 9 visible actions get number keys.

All text actions use the same guarded system prompt: the selected text is treated as **content, never as instructions**, so selected text saying "ignore previous instructions" gets proofread, not obeyed. Output is the result only, with no preamble, in the original language and formatting.

---

## How Improve Prompt works

The meta-prompt is based on Anthropic's and OpenAI's published prompting guidance. It tells the model to:

- be explicit about the task, the audience and what "done" means
- give context and the *why* behind instructions
- say what to do, not only what to avoid
- separate instructions, context, data and examples (XML tags for Claude; headings or delimiters elsewhere)
- use examples only when they reduce ambiguity
- set the output format and length
- add step-by-step reasoning or planning for complex tasks
- cover edge cases and missing information
- ground the prompt in your context (real project, stack, files, audience) instead of generic stand-ins
- **never leave blanks**: when something is missing, make a reasonable assumption, write it into the prompt, and list it so you can correct it
- keep the draft's language and cut padding

The model replies in a fixed tagged format, which the app parses while it streams:

```
<score_before> → <diagnosis> → <improved_prompt> → <changes> → <assumptions> → <score_after>
```

---

## Architecture

```mermaid
flowchart LR
    subgraph Entry points
        W[Main window]
        H[Global hotkey ⌃⌥Space]
        S[Services menu]
        M[Menu bar]
    end
    H --> SB[SelectionBridge<br/>⌘C capture / ⌘V replace]
    SB --> QP[QuickPanel]
    S --> QP
    M --> QP
    W --> AS[AppState]
    QP --> AE
    AS --> AE[ActionEngine<br/>system prompt + messages]
    AE --> PF{ProviderFactory}
    PF --> C1[CLIProvider<br/>claude · codex · gemini]
    PF --> C2[AnthropicProvider<br/>SSE]
    PF --> C3[OpenAICompatibleProvider<br/>SSE]
    C1 & C2 & C3 -->|AsyncThrowingStream&lt;String&gt;| AE
    AE --> R[ForgeResult parser<br/>tolerant of partial streams]
    AS --> HS[(History JSON)]
    AS --> KC[(Keychain)]
```

```
Sources/PromptForge/
├── PromptForgeApp.swift        App, menu bar, commands, AppDelegate
├── AppState.swift              Main-window state, history, settings, engine
├── AppState+System.swift       Hotkey, clipboard and window glue
├── PromptContext.swift         Context profiles, attached files, source app
├── Vault.swift                 Obsidian vaults, [[links]], note ranking
├── Layout.swift                Chip layout math
├── Models.swift                ForgeResult parser, targets, depth, techniques, history
├── MetaPrompt.swift            The prompt-engineering system prompt
├── Actions/Actions.swift       AIAction registry + ActionEngine
├── Providers/
│   ├── Provider.swift          LLMProvider protocol, ProviderKind, settings
│   ├── Keychain.swift          API key storage
│   ├── HTTPProviders.swift     Anthropic + OpenAI-compatible (SSE)
│   └── CLIProvider.swift       Claude Code / Codex / Gemini CLI + PATH resolution
├── System/SystemIntegration.swift   Carbon hotkey, selection capture/paste, Services
└── UI/
    ├── Views.swift             Main window
    ├── QuickPanel.swift        Floating non-activating panel
    ├── SettingsView.swift      Provider / Actions / Context / Shortcut tabs
    └── Theme.swift             Design tokens, ScoreMeter, shared rows, wells and motion
```

**Data on disk**
- History: `~/Library/Application Support/PromptForge/history-v2.json` (last 300 runs)
- Settings and context profiles: `UserDefaults` (`com.dvd90.PromptForge`)
- API keys: Keychain, service `com.dvd90.PromptForge`

Hone shipped as Prompt Forge in 1.0. The bundle ID, Swift module, Keychain service and data paths keep the `PromptForge` name so existing settings, keys and history carry over.

---

## Design

Hone's look is adapted from Dial, a macOS menu-bar time tracker: graphite (dark) and mist (light) surfaces, hairline-ruled sections, one periwinkle accent, and the score drawn as a sunrise-gradient track. Controls and navigation stay standard macOS, and the app follows the system light/dark setting.

- [`DESIGN.md`](DESIGN.md): tokens (colors, type, spacing), components and rules.
- [`PRODUCT.md`](PRODUCT.md): who Hone is for and the principles design decisions follow.

Accessibility: text meets WCAG AA contrast in both appearances, animations respect Reduce Motion, and the score track has a VoiceOver label.

---

## Extending

**Add a built-in action**: append one entry in `Actions/Actions.swift`:
```swift
builtIn("bulletize", "Bullet Points", "list.dash",
        "Convert this text into a clean bulleted list."),
```

**Add a provider**:
1. Conform to the protocol:
   ```swift
   protocol LLMProvider {
       func stream(system: String, messages: [ChatMessage], maxTokens: Int)
           -> AsyncThrowingStream<String, Error>
   }
   ```
2. Add a case to `ProviderKind` and a branch in `ProviderFactory.make`.
3. Add its fields to `ProviderSettingsView`.

**Add a new kind of output** (beyond `promptEngineer` and `transform`): add an `AIAction.Kind` case and handle it in `ActionEngine.system / firstMessage / followUp / displayText`.

---

## Building & testing

```bash
swift build                               # debug build
./build.sh                                # → build/Hone.app (Developer ID signed if installed, else ad-hoc; ./install.sh also accepts Apple Development)
./build.sh --install                      # … and copy to /Applications
./install.sh                              # quit running copy, install, register Services, launch
scripts/make_dmg.sh                       # → build/Hone-<version>.dmg (signed + notarized when a Developer ID cert is installed)
swift scripts/make_icon.swift && iconutil -c icns AppIcon.iconset   # regenerate the icon

swift test                                # unit tests (parser, actions, providers, app state, saved-data decoding)
scripts/coverage.sh                       # unit tests + the 95% coverage gate that CI enforces
PF_LIVE=1 swift test --filter LiveTests   # real calls via your claude + codex logins
```

**CI:** GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) builds the app and runs `scripts/coverage.sh` on a macOS runner for every pull request and every push to `main`: all unit tests must pass and logic code must keep at least 95% line coverage (SwiftUI views and OS glue are excluded by name in the script). Merging into `main` requires a pull request, this check passing, and 1 approval. Live tests never run in CI.

**One-time signing setup** (needed for notarized releases)
1. Xcode → Settings → Accounts → your team → **Manage Certificates… → + → Developer ID Application** (the Account Holder must create it). `build.sh` picks it up automatically.
2. Store notarization credentials in the Keychain (asks for an [app-specific password](https://account.apple.com)):
   ```bash
   xcrun notarytool store-credentials hone-notary --apple-id <your-apple-id> --team-id <your-team-id>
   ```

**Release a new version**
```bash
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString 1.1.0" Info.plist
scripts/make_dmg.sh
gh release create v1.1.0 build/Hone-1.1.0.dmg --title "v1.1.0" --notes "…"
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Hone can't be opened" | Only for ad-hoc builds (not notarized): `xattr -dr com.apple.quarantine "/Applications/Hone.app"` |
| Hotkey does nothing | Another app may own the combo. Pick another in Settings → Shortcut |
| Hotkey uses the clipboard instead of the selection; no Replace button | Grant Accessibility. Builds signed with Developer ID or Apple Development keep the grant; **after every rebuild** of an ad-hoc build, remove and re-add it in the Accessibility list |
| "Couldn't find the `claude` command" | Settings → Provider shows where it looked. Install the CLI, or make sure it's on your login-shell `PATH` |
| `Claude Code failed: … login` | Run `claude` in Terminal and sign in |
| Gemini: "Please set an Auth method" | Run `gemini` once and choose "Login with Google" |
| OpenAI-compatible: 404 | The base URL must end at `/v1` (e.g. `https://api.openai.com/v1`) and the model ID must exist |
| Services entries missing | Run `/System/Library/CoreServices/pbs -update`, then log out and back in |

---

## Privacy & security

- No servers, accounts or analytics. The app talks only to the provider you select (or runs its local CLI).
- API keys are stored in the macOS **Keychain**, never in plain text.
- Selected text is wrapped in delimiters and labelled as content, which hardens the actions against prompt injection. Context (profiles, notes, files, window titles, Obsidian notes) is delimited the same way, and its closing tags are escaped so a file can't break out of its block.
- Context goes only to the provider you chose. Turn off the window-title capture in **Settings → Context**, and remove any chip before running. Obsidian notes are off until you choose a vault.
- CLI calls run **without tools**, in a read-only or plan mode and an empty temp folder, so a model can't touch your files.
- After capturing a selection with ⌘C, the app restores your clipboard (all types).

---

## Contributing

Contributions of every size are welcome, from a typo fix to a new provider. If you're unsure whether an idea fits, start a thread in [Discussions](../../discussions) before writing code.

### Where help is most useful
- **Gemini CLI provider:** it hasn't been tested end to end yet. Try it with your Google login and report what happens.
- **Hotkey and Replace across apps:** capturing a selection with ⌘C and pasting back with ⌘V depends on the target app. Report apps where it misbehaves (browsers, Electron apps, terminals, editors), with steps.
- **New built-in actions:** each is one entry in `Actions/Actions.swift` (see [Extending](#extending)).
- **New providers:** conform to `LLMProvider` and wire it into `ProviderFactory` and Settings.
- **Tests:** more coverage for `ActionEngine`, the SSE parsing in `HTTPProviders.swift`, and `ForgeResult.parse` on unusual model output.
- **Accessibility and localization:** VoiceOver and keyboard-only walkthroughs, and translated UI strings.

### Reporting a bug
Open an [issue](../../issues) with your macOS version, Hone version, provider, the steps to reproduce, and what you expected instead. Leave out API keys and any private text you were working on.

### Sending a pull request
1. Fork the repo and create a branch from `main`.
2. Build and test. `swift build` should finish with zero warnings, and `scripts/coverage.sh` should pass: all tests green and at least 95% line coverage on logic code. Add tests for new logic. `PF_LIVE=1 swift test --filter LiveTests` makes real calls on your own Claude Code and Codex logins, and is only needed when you change providers or prompts.
3. Keep the pull request focused on one change, and say what you tested and on which macOS version. CI runs the same build, tests and coverage gate; a pull request merges once that check passes and a maintainer approves it.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

### Ground rules
These keep Hone private, native and dependency-free:
- No third-party packages, telemetry, or new network destinations without discussing it first.
- API keys live only in the Keychain.
- Selected text is content, never instructions: keep it inside the `<text>` / `<draft_prompt>` delimiters.
- Use standard macOS controls and follow [`DESIGN.md`](DESIGN.md) for colors, spacing and components.
- Don't change the bundle ID, the history file format or the settings keys without a migration, so existing users keep their data.
- Swift 5 language mode, macOS 14+.

[`CLAUDE.md`](CLAUDE.md) holds the same rules in more detail (it doubles as guidance for AI coding agents).

### Security
For a security problem, please don't open a public issue. Report it privately through the repository's **Security** tab (**Report a vulnerability**).

---

## License

Hone is released under the [MIT License](LICENSE).

---

<sub>Built with SwiftUI · macOS 14+ · no third-party dependencies.</sub>
