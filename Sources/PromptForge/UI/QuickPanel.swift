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
    @Published var canReplace = false
    @Published var copied = false
    /// Where the user came from ("App — Window title"), sent as Improve Prompt context; removable in the panel.
    @Published var source = ""
    /// Obsidian notes for this text, found in the background after the panel opens; removable chips.
    @Published var vaultNotes: [Attachment] = []

    weak var state: AppState?
    private var panel: KeyablePanel?
    private var previousApp: NSRunningApplication?
    private var task: Task<Void, Never>?
    private var notesTask: Task<Void, Never>?
    private var removedNotes: Set<String> = []
    private var sentMessage: ChatMessage?

    // MARK: Entry points

    /// Hotkey: grab the current selection in whatever app is frontmost.
    func presentFromSelection() async {
        previousApp = NSWorkspace.shared.frontmostApplication
        let source = state?.includeSourceApp == true ? SelectionBridge.sourceDescription(of: previousApp) : ""
        if !SelectionBridge.isTrusted { SelectionBridge.requestTrust() }
        let captured = await SelectionBridge.captureSelection()
        present(text: captured.text, canReplace: captured.fromSelection, autoRun: nil, source: source)
    }

    /// Services menu / clipboard: text is handed to us directly.
    func present(text: String, canReplace: Bool, autoRun actionID: String?, source: String = "") {
        if previousApp == nil || previousApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        task?.cancel()
        sourceText = text
        self.source = source
        self.canReplace = canReplace && SelectionBridge.isTrusted
        output = ""; raw = ""; action = nil; phase = .choosing
        removedNotes = []
        findVaultNotes()
        showPanel()
        if let id = actionID, let a = state?.allActions.first(where: { $0.id == id }) { run(a) }
    }

    /// Looks up vault notes for this text in the background (again when the profile changes); chips appear when done.
    func findVaultNotes() {
        let text = sourceText, source = source, removed = removedNotes
        vaultNotes = []
        notesTask?.cancel()
        notesTask = Task { [weak self] in
            guard let found = await self?.state?.relevantNotes(text: text, notes: "", source: source, excluding: removed),
                  !Task.isCancelled, let self else { return }
            self.vaultNotes = found.filter { !self.removedNotes.contains($0.name) }
        }
    }

    func removeVaultNote(_ note: Attachment) {
        removedNotes.insert(note.name)
        vaultNotes.removeAll { $0.name == note.name }
    }

    // MARK: Actions

    func run(_ a: AIAction) {
        guard let state else { return }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        action = a
        output = ""; raw = ""
        guard !text.isEmpty else { phase = .failed("No text. Select some text (or copy it) and try again."); return }

        let provider: LLMProvider
        do { provider = try ProviderFactory.make(state.providerSettings) } catch {
            phase = .failed(error.localizedDescription); return
        }
        phase = .running
        // Exactly the note chips on screen: a lookup still running (or a Services auto-run) adds no notes,
        // so nothing reaches the provider that the user didn't see.
        let message = ActionEngine.firstMessage(action: a, text: text, options: state.panelOptions(source: source, vaultNotes: vaultNotes))
        sentMessage = message
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
                if final.isEmpty {
                    self.phase = .failed("The model returned nothing usable. Try again.")
                } else {
                    self.phase = .done
                    self.state?.recordHistory(action: a, draft: text, raw: raw, conversation: [message], notes: "")
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
        output = ""; raw = ""; action = nil
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
        guard let state, let a = action, let message = sentMessage else { return }
        state.load(action: a, draft: sourceText, raw: raw, message: message, source: source)
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
            host.safeAreaRegions = []   // lay out under the transparent title bar; the header shares its row
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
            // Shares the title bar row with the close button instead of leaving an empty band above.
            HStack(spacing: 7) {
                Circle().fill(Theme.dot).frame(width: 8, height: 8)
                Text("Hone").font(.headline)
                Spacer()
                Text(state.providerSettings.kind.shortLabel).font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.leading, 18)
            .frame(height: 20)

            Text(c.sourceText.isEmpty ? "No text found. Select text in any app (or copy it), then press the hotkey." : c.sourceText)
                .lineLimit(c.phase == .choosing ? 4 : 2)
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .field(Theme.inputFill)

            Divider().padding(.vertical, 2)

            switch c.phase {
            case .choosing:
                chooser
            default:
                resultView
            }
        }
        .padding([.horizontal, .bottom], 14)
        .padding(.top, 4)
        .frame(width: 560)
        .background(Theme.ground)
        .background(Button("") { c.close() }.keyboardShortcut(.cancelAction).opacity(0))
        .motion(c.phase)
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
                            if i < 9 { Text("\(i + 1)").font(.caption.monospaced()).foregroundStyle(Theme.muted) }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .modifier(NumberShortcut(index: i))
                    .disabled(c.sourceText.isEmpty)
                }
            }
            if !state.contextProfiles.isEmpty || !c.source.isEmpty || !c.vaultNotes.isEmpty { promptContextRow }
            Text("Press 1–9 or click · Esc to close")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
        .onChange(of: state.contextProfileID) { c.findVaultNotes() }   // the new profile may [[link]] other notes
    }

    /// What Improve Prompt will know: the selected profile, the app the user came from and vault notes (removable).
    private var promptContextRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            promptContextHeader
            if !c.vaultNotes.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(c.vaultNotes) { note in
                        ContextChip(title: note.name, icon: "book.closed") { c.removeVaultNote(note) }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var promptContextHeader: some View {
        HStack(spacing: 8) {
            Text("Prompt context").font(.caption).foregroundStyle(Theme.muted)
            if !state.contextProfiles.isEmpty {
                Picker("Context profile", selection: Binding(get: { state.contextProfileID },
                                                             set: { state.contextProfileID = $0 })) {
                    Text("No profile").tag(UUID?.none)
                    ForEach(state.contextProfiles) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            if !c.source.isEmpty {
                ContextChip(title: c.source, icon: "macwindow") { c.source = "" }
            }
            Spacer(minLength: 0)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let a = c.action { Label(a.name, systemImage: a.icon).font(.subheadline.weight(.semibold)) }
                if c.phase == .running && c.action?.kind != .promptEngineer { ProgressView().controlSize(.small) }
                Spacer()
            }
            if c.action?.kind == .promptEngineer {
                let r = ForgeResult.parse(c.raw)
                ScoreMeter(before: r.scoreBefore, after: r.scoreAfter, isRunning: c.phase == .running, compact: true)
            }

            if case let .failed(msg) = c.phase {
                // Red only on the icon: red body text fails WCAG AA.
                Label { Text(msg).textSelection(.enabled) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
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
                .field()
                if c.action?.kind == .promptEngineer, c.phase == .done,
                   case let assumed = ForgeResult.parse(c.raw).assumptions, !assumed.isEmpty {
                    // Replace pastes the prompt straight into another app, so show what it took for granted.
                    Text("Assumed: " + assumed.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: "; "))
                        .font(.caption).foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .help(assumed.map { "• " + $0 }.joined(separator: "\n"))
                }
            }

            Divider().padding(.vertical, 2)
            HStack {
                // Dial's footer: quiet text actions on the left, the real choices on the right.
                HStack(spacing: 18) {
                    Button { c.back() } label: { Label("Actions", systemImage: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                    Button("Open in App") { c.openInApp() }
                        .disabled(c.phase != .done)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.muted)
                Spacer()
                // One primary action: Replace when it's available, otherwise Copy.
                if c.canReplace {
                    copyButton
                    Button { c.replace() } label: { Label("Replace", systemImage: "arrow.uturn.left") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(c.phase != .done)
                } else {
                    copyButton.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var copyButton: some View {
        Button { c.copyOutput() } label: {
            Label(c.copied ? "Copied" : "Copy", systemImage: c.copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(c.output.isEmpty)
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
