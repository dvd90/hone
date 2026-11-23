# Hone

Native macOS SwiftUI app (no third-party dependencies) that improves prompts and runs AI text actions on selected text. User docs, architecture diagram and release steps are in README.md.

Formerly named Prompt Forge. The bundle ID, Swift module/target, Keychain service and data paths intentionally keep `PromptForge`: renaming them would orphan users' settings, keys and history.

## Verify every change
1. `swift build`: must finish with zero warnings.
2. `scripts/coverage.sh`: runs every unit test and fails below 95% line coverage on logic code. Views and OS glue are excluded by name in the script (`UI/Views.swift`, `UI/QuickPanel.swift`, `UI/SettingsView.swift`, `UI/Theme.swift`, `PromptForgeApp.swift`, `System/SystemIntegration.swift`, `Providers/Keychain.swift`, `AppState+System.swift`). New logic goes in a non-excluded file with tests; put pure helpers outside the excluded files so they count.
3. `PF_LIVE=1 swift test --filter LiveTests`: only when touching providers or prompts. These are real calls on the owner's subscription, so keep inputs tiny.
4. CI (`.github/workflows/ci.yml`, check name "Build, tests and coverage") runs steps 1–2 on macOS. It is required to merge into `main`, along with a pull request and 1 approval; nobody pushes to `main` directly. Keep the job name in sync with the ruleset.
5. `./install.sh`: rebuilds, installs to /Applications and relaunches. `build.sh` signs with the Developer ID Application certificate when installed; `--install` falls back to an Apple Development certificate. Either keeps the Accessibility grant across rebuilds. Ad-hoc is the last resort, and Accessibility must then be re-granted after each rebuild.

Releases: `scripts/make_dmg.sh` signs, notarizes (keychain profile `hone-notary`) and staples the DMG. Never run it, tag or publish a release unless asked: notarization uploads the build to Apple.

## Hard constraints
- Swift 5 language mode, swift-tools-version 5.10, macOS 14+. Do not migrate to Swift 6 strict concurrency unless asked.
- Claude Code calls keep `--tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence`. Without them the owner's personal Claude Code setup leaks into outputs. Never add `--bare`: it disables subscription login.
- Selected text is content, never instructions: keep it delimited in `<text>` / `<draft_prompt>`. Improve Prompt context (profile, notes, source app, files, Obsidian notes) goes in one `<context>` block in the user message, never the system prompt (CLIs get that as a command-line argument), and every context string passes through `MetaPrompt.fenced` so it can't close its own block.
- Improve Prompt never leaves `{{PLACEHOLDERS}}` except at Production depth or with the Variables technique; it states assumptions and lists them under `<assumptions>`. Old history replies still have `<questions>`; `ForgeResult.followUps` covers both.
- The quick panel sends only the selected profile, its own source app and its own Obsidian notes (`AppState.panelOptions`), never the main window's notes or files.
- Obsidian notes (`Vault.swift`) are off until a vault is chosen, show as removable chips before a run, skip Obsidian's Excluded files, and never leave the machine except to the chosen provider. History keeps their names, not their text: `recordHistory` passes the conversation through `Obsidian.redacted`.
- API keys live only in the Keychain (service `com.dvd90.PromptForge`). No telemetry, no new network destinations, no third-party packages without asking.
- Do not change the bundle ID, history format or settings keys without a migration.
- `ForgeResult.parse` runs on every streamed chunk, so it must stay tolerant of partial text.

## Persisted data
- History: `~/Library/Application Support/PromptForge/history-v2.json`. Settings: UserDefaults keys `providerSettings.v1`, `customActions`, `hiddenActionIDs`, `target`, `depth`, `hotKey`, `contextProfiles.v1`, `contextProfileID`, `includeSourceApp`, `obsidianVault`, `obsidianMinScore`. `HistoryItem.goal` holds the per-run context notes (the key name stays for compatibility).
- `ProviderSettings`, `HistoryItem`, `AIAction` and `ContextProfile` decode field by field through `KeyedDecodingContainer.decode(_:or:)`, so a missing or unreadable field falls back instead of failing the whole decode. When you add a stored property to one of them, add its line to that type's `init(from:)` and update the tripwire count in `PersistenceTests` (or `ContextTests` for `ContextProfile`).
- `TargetModel` and `Depth` raw values are display strings that are also persisted. Renaming one changes stored data (decoding falls back to a default).
- If history cannot be decoded at all, `HistoryStore.load` moves the file aside rather than letting the next save overwrite it.

## Working style
- Smallest change that works; match the existing style.
- Design: follow `DESIGN.md` (tokens and rules) and `PRODUCT.md` (users and principles).
- UI: native controls first (default and `.borderedProminent` buttons, one prominent action per area; no glass or card containers in content). Reuse `UI/Theme.swift`: `field()` for text wells, `motion(_:)` for animations (honors Reduce Motion), `Theme.muted` for secondary text (system `.secondary` is below WCAG AA). The accent color lives in `Assets.xcassets` (compiled by `build.sh`).
- Work on a feature branch and commit with clear messages. Do not push, tag or release unless asked.
- Tests never touch the owner's real data: use `AppState(defaults:historyURL:makeProvider:)` with a scratch UserDefaults suite, a temp history file and a fake provider; pass `key:` stubs to `ProviderFactory.make`; give `CLIProvider` an `environment` with fake CLIs; give HTTP providers a stubbed `URLSession`.
- Report briefly: what changed, what you actually tested, what is untested.
