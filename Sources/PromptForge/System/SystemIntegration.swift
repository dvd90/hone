import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Global hotkey (Carbon; needs no special permission)

enum HotKeyPreset: String, CaseIterable, Identifiable, Codable {
    case ctrlOptSpace, optSpace, cmdShiftSpace, ctrlOptP, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ctrlOptSpace: return "⌃⌥Space"
        case .optSpace: return "⌥Space"
        case .cmdShiftSpace: return "⇧⌘Space"
        case .ctrlOptP: return "⌃⌥P"
        case .off: return "Disabled"
        }
    }

    var keyCode: UInt32 {
        self == .ctrlOptP ? UInt32(kVK_ANSI_P) : UInt32(kVK_Space)
    }

    var modifiers: UInt32 {
        switch self {
        case .ctrlOptSpace, .ctrlOptP: return UInt32(controlKey | optionKey)
        case .optSpace: return UInt32(optionKey)
        case .cmdShiftSpace: return UInt32(cmdKey | shiftKey)
        case .off: return 0
        }
    }
}

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hk = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hk.action() }
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5046_4F47), id: 1) // 'PFOG'
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

// MARK: - Reading the selection / pasting back (needs Accessibility permission)

enum SelectionBridge {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copies the frontmost app's selection via ⌘C, then restores the clipboard.
    /// Falls back to the current clipboard text when not trusted or nothing was selected.
    @MainActor
    static func captureSelection() async -> (text: String, fromSelection: Bool) {
        let pb = NSPasteboard.general
        let clipboardText = pb.string(forType: .string) ?? ""
        guard isTrusted else { return (clipboardText, false) }

        let saved = snapshot()
        let before = pb.changeCount
        try? await Task.sleep(for: .milliseconds(60)) // let the hotkey modifiers settle
        postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(25))
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before, let selected = pb.string(forType: .string),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (clipboardText, false)
        }
        restore(saved)
        return (selected, true)
    }

    /// Puts text on the clipboard, re-activates the source app and sends ⌘V.
    @MainActor
    static func paste(_ text: String, into app: NSRunningApplication?) async {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard isTrusted else { return }
        app?.activate()
        try? await Task.sleep(for: .milliseconds(220))
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        NSPasteboard.general.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        } ?? []
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !items.isEmpty else { return }
        pb.writeObjects(items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        })
    }
}

// MARK: - macOS Services menu (right-click → Services → Prompt Forge…; no permission needed)

final class ServiceProvider: NSObject {
    var onText: ((_ text: String, _ actionID: String?) -> Void)?

    @objc func improvePrompt(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let s = pboard.string(forType: .string) { onText?(s, AIAction.improvePrompt.id) }
    }

    @objc func quickActions(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let s = pboard.string(forType: .string) { onText?(s, nil) }
    }
}
