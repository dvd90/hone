import AppKit

/// AppState's macOS glue: hotkey, Services, windows, pasteboard and the live connection test.
/// Excluded from the coverage gate because unit tests can't drive these OS facilities.
extension AppState {
    // MARK: Startup wiring

    func startSystemIntegration() {
        applyHotKey()
        serviceProvider.onText = { [weak self] text, actionID in
            Task { @MainActor in self?.quickPanel.present(text: text, canReplace: true, autoRun: actionID) }
        }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    func applyHotKey() {
        hotKeyRef = nil
        guard hotKey != .off else { return }
        hotKeyRef = GlobalHotKey(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers) { [weak self] in
            Task { @MainActor in await self?.quickPanel.presentFromSelection() }
        }
    }

    func quickActionsOnClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        quickPanel.present(text: text, canReplace: false, autoRun: nil)
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let open = openMainWindow { open() }
        else { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        justCopied = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.justCopied = false
        }
    }

    func pasteDraft() {
        if let s = NSPasteboard.general.string(forType: .string) { draft = s }
    }

    func testConnection() async -> String {
        do {
            let provider = try makeProvider(providerSettings)
            var out = ""
            for try await c in provider.stream(system: "Reply with the single word OK.",
                                               messages: [ChatMessage(role: "user", content: "ping")], maxTokens: 10) {
                out += c
            }
            return "✓ \(providerSettings.kind.shortLabel) replied: \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }
}
