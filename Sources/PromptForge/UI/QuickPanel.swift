import AppKit
import SwiftUI

/// A floating panel that can take keyboard focus without activating the app,
/// so the app you were typing in stays frontmost for "Replace".
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickPanelController: ObservableObject {
    enum Phase: Equatable { case choosing, running, done, failed(String) }

    @Published var sourceText = ""
    @Published var output = ""
    @Published var raw = ""
    @Published var phase: Phase = .choosing
    @Published var action: AIAction?
    @Published var scoreLine: String?
    @Published var canReplace = false
    @Published var copied = false

    weak var state: AppState?
    private var panel: KeyablePanel?
    private var previousApp: NSRunningApplication?
    private var task: Task<Void, Never>?

    // MARK: Entry points

    /// Hotkey: grab the current selection in whatever app is frontmost.
    func presentFromSelection() async {
        previousApp = NSWorkspace.shared.frontmostApplication
        if !SelectionBridge.isTrusted { SelectionBridge.requestTrust() }
        let captured = await SelectionBridge.captureSelection()
        present(text: captured.text, canReplace: captured.fromSelection, autoRun: nil)
    }

    /// Services menu / clipboard: text is handed to us directly.
    func present(text: String, canReplace: Bool, autoRun actionID: String?) {
        if previousApp == nil || previousApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        task?.cancel()
        sourceText = text
        self.canReplace = canReplace && SelectionBridge.isTrusted
        output = ""; raw = ""; scoreLine = nil; action = nil; phase = .choosing
        showPanel()
        if let id = actionID, let a = state?.allActions.first(where: { $0.id == id }) { run(a) }
    }

    // MARK: Actions

    func run(_ a: AIAction) {
        guard let state else { return }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        action = a
        output = ""; raw = ""; scoreLine = nil
        guard !text.isEmpty else { phase = .failed("No text. Select some text (or copy it) and try again."); return }

        let provider: LLMProvider
        do { provider = try ProviderFactory.make(state.providerSettings) } catch {
            phase = .failed(error.localizedDescription); return
        }
        phase = .running
        let options = state.promptOptions
        let message = ActionEngine.firstMessage(action: a, text: text, options: options)
        let system = ActionEngine.system(for: a)

        task?.cancel()
        task = Task { [weak self] in
            var raw = ""
            do {
                for try await chunk in provider.stream(system: system, messages: [message], maxTokens: 8000) {
                    raw += chunk
                    guard let self else { return }
                    self.raw = raw
                    self.output = ActionEngine.displayText(action: a, raw: raw)
                }
                guard let self else { return }
                let final = ActionEngine.displayText(action: a, raw: raw)
                self.output = final
                if a.kind == .promptEngineer {
                    let r = ForgeResult.parse(raw)
                    if let b = r.scoreBefore, let after = r.scoreAfter { self.scoreLine = "\(b) → \(after)" }
                }
                if final.isEmpty {
                    self.phase = .failed("The model returned nothing usable. Try again.")
                } else {
                    self.phase = .done
                    self.state?.recordHistory(action: a, draft: text, raw: raw, conversation: [message, ChatMessage(role: "assistant", content: raw)])
                }
            } catch {
                guard let self else { return }
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func back() {
        task?.cancel()
        phase = .choosing
        output = ""; raw = ""; action = nil; scoreLine = nil
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copied = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.copied = false
        }
    }

    func replace() {
        guard !output.isEmpty else { return }
        let text = output, app = previousApp
        close()
        Task { await SelectionBridge.paste(text, into: app) }
    }

    func openInApp() {
        guard let state, let a = action else { return }
        state.load(action: a, draft: sourceText, raw: raw)
        close()
        state.showMainWindow()
    }

    func close() {
        task?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: Window

    private func showPanel() {
        guard let state else { return }
        if panel == nil {
            let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                                 styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable],
                                 backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            let host = NSHostingController(rootView: QuickPanelView(c: self).environmentObject(state))
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            panel = p
        }
        guard let panel else { return }

        // Position near the mouse, kept on screen.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            if origin.y < vf.minY + 8 { origin.y = min(mouse.y + 16, vf.maxY - size.height - 8) }
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }
}

struct QuickPanelView: View {
    @ObservedObject var c: QuickPanelController
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                Text("Hone").font(.headline)
                Spacer()
                Text(state.providerSettings.kind.shortLabel)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text(c.sourceText.isEmpty ? "No text found. Select text in any app (or copy it), then press the hotkey." : c.sourceText)
                .lineLimit(c.phase == .choosing ? 4 : 2)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

            switch c.phase {
            case .choosing:
                chooser
            default:
                resultView
            }
        }
        .padding(14)
        .padding(.top, 12)
        .frame(width: 560)
        .background(Button("") { c.close() }.keyboardShortcut(.cancelAction).opacity(0))
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(state.actions.enumerated()), id: \.element.id) { i, a in
                    Button { c.run(a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.icon).frame(width: 16)
                            Text(a.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if i < 9 { Text("\(i + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary) }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .modifier(NumberShortcut(index: i))
                    .disabled(c.sourceText.isEmpty)
                }
            }
            Text("Press 1–9 or click · Esc to close")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let a = c.action { Label(a.name, systemImage: a.icon).font(.subheadline.weight(.semibold)) }
                if c.phase == .running { ProgressView().controlSize(.small) }
                Spacer()
                if let s = c.scoreLine { Text("Score \(s)").font(.caption.monospacedDigit()).foregroundStyle(.green) }
            }

            if case let .failed(msg) = c.phase {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    Text(c.output.isEmpty ? "…" : c.output)
                        .font(c.action?.kind == .promptEngineer ? .system(.callout, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 320)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            }

            HStack {
                Button { c.back() } label: { Label("Actions", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Open in App") { c.openInApp() }
                    .disabled(c.phase != .done)
                Spacer()
                Button { c.copyOutput() } label: {
                    Label(c.copied ? "Copied" : "Copy", systemImage: c.copied ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(c.output.isEmpty)
                if c.canReplace {
                    Button { c.replace() } label: { Label("Replace", systemImage: "arrow.uturn.left") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(c.phase != .done)
                }
            }
        }
    }
}

private struct NumberShortcut: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        } else {
            content
        }
    }
}
