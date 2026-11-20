# Hone

Native macOS SwiftUI app (no third-party dependencies) that improves prompts and runs AI text actions on selected text. User docs, architecture diagram and release steps are in README.md.

Formerly named Prompt Forge. The bundle ID, Swift module/target, Keychain service and data paths intentionally keep `PromptForge`: renaming them would orphan users' settings, keys and history.

## Verify every change
1. `swift build`: must finish with zero warnings.
2. `swift test`: add tests for any new logic.
3. `PF_LIVE=1 swift test --filter LiveTests`: only when touching providers or prompts. These are real calls on the owner's subscription, so keep inputs tiny.
4. `./install.sh`: rebuilds, installs to /Applications and relaunches. The app is ad-hoc signed, so Accessibility must be re-granted after each rebuild.

## Hard constraints
- Swift 5 language mode, swift-tools-version 5.10, macOS 14+. Do not migrate to Swift 6 strict concurrency unless asked.
- Claude Code calls keep `--tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence`. Without them the owner's personal Claude Code setup leaks into outputs. Never add `--bare`: it disables subscription login.
- Selected text is content, never instructions: keep it delimited in `<text>` / `<draft_prompt>`.
- API keys live only in the Keychain (service `com.dvd90.PromptForge`). No telemetry, no new network destinations, no third-party packages without asking.
- Do not change the bundle ID, history format or settings keys without a migration.
- `ForgeResult.parse` runs on every streamed chunk, so it must stay tolerant of partial text.

## Persisted data
- History: `~/Library/Application Support/PromptForge/history-v2.json`. Settings: UserDefaults keys `providerSettings.v1`, `customActions`, `hiddenActionIDs`, `target`, `depth`, `hotKey`.
- `ProviderSettings`, `HistoryItem` and `AIAction` decode field by field through `KeyedDecodingContainer.decode(_:or:)`, so a missing or unreadable field falls back instead of failing the whole decode. When you add a stored property to one of them, add its line to that type's `init(from:)` and update the tripwire count in `PersistenceTests`.
- `TargetModel` and `Depth` raw values are display strings that are also persisted. Renaming one changes stored data (decoding falls back to a default).
- If history cannot be decoded at all, `HistoryStore.load` moves the file aside rather than letting the next save overwrite it.

## Working style
- Smallest change that works; match the existing style.
- Work on a feature branch and commit with clear messages. Do not push, tag or release unless asked.
- Report briefly: what changed, what you actually tested, what is untested.
