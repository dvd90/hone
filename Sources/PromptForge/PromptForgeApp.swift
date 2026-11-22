import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A CLI that exits before reading all of stdin (large context) must not kill Hone with SIGPIPE;
        // the write then just fails and the CLI's own error is reported.
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.regular)
        AppState.shared.startSystemIntegration()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep running in the menu bar (and keep the hotkey alive) after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.showMainWindow() }
        return true
    }
}

@main
struct PromptForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        Window("Hone", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { state.reset() }.keyboardShortcut("n")
            }
            CommandMenu("Actions") {
                Button("Run \(state.selectedAction.name)") { state.run() }
                    .keyboardShortcut(.return)
                    .disabled(state.isRunning)
                Button("Stop") { state.cancel() }
                    .keyboardShortcut(".")
                    .disabled(!state.isRunning)
                Divider()
                Button("Quick Actions on Clipboard") { state.quickActionsOnClipboard() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView().environmentObject(state)
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(state)
        } label: {
            MenuBarLabel().environmentObject(state)
        }
    }
}

/// Always rendered, so it's a reliable place to capture `openWindow` for use outside SwiftUI.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "wand.and.stars")
            .onAppear { state.openMainWindow = { openWindow(id: "main") } }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button("Quick Actions on Selection (\(state.hotKey.label))") {
            Task { await state.quickPanel.presentFromSelection() }
        }
        .disabled(state.hotKey == .off && !SelectionBridge.isTrusted)
        Button("Quick Actions on Clipboard") { state.quickActionsOnClipboard() }
        Divider()
        Text("Provider: \(state.providerSettings.kind.shortLabel)")
        Button("Open Hone") { state.showMainWindow() }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Hone") { NSApp.terminate(nil) }
    }
}
