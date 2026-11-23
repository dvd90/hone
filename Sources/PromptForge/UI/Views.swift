import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            HistorySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            // Sidebar + both minimum widths stay within the window's 1000 pt minimum.
            HSplitView {
                InputPane().frame(minWidth: 340, idealWidth: 420)
                OutputPane().frame(minWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The pane ground runs up under a transparent toolbar over the detail column only,
            // so the native sidebar keeps its full height.
            .background(Theme.ground)
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { state.reset() } label: { Label("New", systemImage: "square.and.pencil") }
                    .help("New (⌘N)")
            }
        }
        .onAppear { state.openMainWindow = { openWindow(id: "main") } }
    }
}

// MARK: - Sidebar

struct HistorySidebar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: Binding(
            get: { state.currentID },
            set: { id in
                if let id, id != state.currentID, let item = state.history.first(where: { $0.id == id }) {
                    state.open(item)
                }
            })) {
            Section("History") {
                ForEach(state.history) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).lineLimit(2).font(.body.weight(.medium))
                        HStack(spacing: 4) {
                            if let r = item.result, let b = r.scoreBefore, let a = r.scoreAfter {
                                Text("\(b)→\(a)").monospacedDigit().fixedSize()
                            } else {
                                Text(item.actionName).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Text(item.date.formatted(.relative(presentation: .named, unitsStyle: .narrow)))
                                .lineLimit(1).fixedSize()
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 3)
                    .tag(item.id)
                    .contextMenu {
                        Button("Copy result") { state.copy(item.output) }
                        Button("Delete", role: .destructive) { state.delete(item) }
                    }
                }
            }
        }
        .overlay {
            if state.history.isEmpty { ContentUnavailableView("No history yet", systemImage: "clock") }
        }
    }
}

// MARK: - Input

struct InputPane: View {
    @EnvironmentObject var state: AppState
    @State private var choosingFiles = false

    private var isPrompt: Bool { state.selectedAction.kind == .promptEngineer }

    /// Picking another action by hand starts fresh. Opening history or "Open in App" sets the action
    /// programmatically and must keep the loaded result, so clearing lives here, not in an onChange.
    private var actionSelection: Binding<String> {
        Binding(get: { state.selectedActionID }, set: { id in
            guard id != state.selectedActionID else { return }
            state.selectedActionID = id
            state.clearOutput()
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("Action", selection: actionSelection) {
                        ForEach(state.actions) { a in Label(a.name, systemImage: a.icon).tag(a.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Text("\(state.draft.count) chars").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    Button("Paste") { state.pasteDraft() }.controlSize(.small)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $state.draft)
                        .font(isPrompt ? .system(.body, design: .monospaced) : .body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    if state.draft.isEmpty {
                        Text(isPrompt ? "Paste or type a prompt to improve…" : "Paste or type the text to work on…")
                            .font(isPrompt ? .system(.body, design: .monospaced) : .body)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
                .field(Theme.inputFill)
                .frame(minHeight: 160, maxHeight: .infinity)
            }
            .padding(16)

            Divider()
            Group {
                if isPrompt { promptOptions }
                else {
                    Text(state.selectedAction.instruction)
                        .font(.callout).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)

            Divider()
            HStack(spacing: 10) {
                if state.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { state.cancel() }
                }
                Text(state.providerSettings.kind.shortLabel).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button { state.run() } label: {
                    Label(isPrompt ? "Improve prompt" : state.selectedAction.name, systemImage: state.selectedAction.icon)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Run (⌘↩)")
                .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.ground)
    }

    private var promptOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            contextSection
            OptionRow(label: "Target") {
                Picker("Target", selection: $state.target) {
                    ForEach(TargetModel.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            OptionRow(label: "Depth") {
                Picker("Depth", selection: $state.depth) {
                    ForEach(Depth.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                OptionRow(label: "Techniques") {
                    if state.techniques.isEmpty {
                        Text("Auto").font(.callout).foregroundStyle(Theme.muted)
                    } else {
                        Button("Clear \(state.techniques.count)") { state.techniques.removeAll() }
                            .buttonStyle(.link).controlSize(.small)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(Technique.allCases) { t in
                        Toggle(isOn: Binding(
                            get: { state.techniques.contains(t) },
                            set: { on in if on { state.techniques.insert(t) } else { state.techniques.remove(t) } })) {
                            Label(t.rawValue, systemImage: t.icon)
                        }
                        .toggleStyle(.button)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help(t.instruction)
                    }
                }
            }
        }
    }
}

extension InputPane {
    /// Profile, per-run notes, attached files, vault notes and the source app: what Improve Prompt knows about the situation.
    var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Context").foregroundStyle(Theme.muted)
                Spacer(minLength: 12)
                if state.contextProfiles.isEmpty {
                    SettingsLink { Text("Add profile…") }
                        .buttonStyle(.link).controlSize(.small)
                        .help("Save reusable notes about you or a project in Settings → Context")
                } else {
                    Picker("Context profile", selection: $state.contextProfileID) {
                        Text("No profile").tag(UUID?.none)
                        ForEach(state.contextProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170)
                    .help("Saved notes about you or a project, sent with every Improve Prompt run")
                }
                Button { choosingFiles = true } label: { Image(systemName: "paperclip") }
                    .help("Attach text files (or drop them here)")
                    .accessibilityLabel("Attach files")
            }
            TextField("Context", text: $state.notes, prompt: Text(""), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .placeholder("Project, audience, constraints, examples…", when: state.notes.isEmpty)
                .accessibilityHint("Facts about your situation for this run: project, audience, constraints, examples")
            if !state.sourceApp.isEmpty || !state.attachments.isEmpty || !state.vaultNotes.isEmpty {
                FlowLayout(spacing: 6) {
                    if !state.sourceApp.isEmpty {
                        ContextChip(title: state.sourceApp, icon: "macwindow") { state.sourceApp = "" }
                    }
                    ForEach(state.attachments) { file in
                        ContextChip(title: file.name, icon: "doc.text") { state.removeAttachment(file) }
                    }
                    ForEach(state.vaultNotes) { note in
                        ContextChip(title: note.name, icon: "book.closed") { state.removeVaultNote(note) }
                    }
                }
            }
        }
        // Vault notes follow the draft, debounced so typing doesn't rescan the vault on every key.
        .task(id: [state.draft, state.notes, state.sourceApp, state.obsidianVault, "\(state.obsidianMinScore)",
                   state.contextProfileID?.uuidString ?? ""]) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { await state.refreshVaultNotes() }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { state.attach(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.attach(urls.filter(\.isFileURL))
            return true
        }
    }
}

/// A removable context item: a file, a vault note or the app the user came from.
struct ContextChip: View {
    let title: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.muted)
            Text(title).lineLimit(1).truncationMode(.middle)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("Remove \(title)")
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Theme.fieldFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .help(title)
    }
}

/// Lays children out left to right and wraps like text (used for the technique chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.arrange(subviews.map { $0.sizeThatFits(.unspecified) }, width: proposal.width ?? .infinity, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = Self.arrange(subviews.map { $0.sizeThatFits(.unspecified) }, width: bounds.width, spacing: spacing).origins
        for (view, p) in zip(subviews, origins) {
            view.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

}

// MARK: - Output

struct OutputPane: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.raw.isEmpty && !state.isRunning && state.errorMessage == nil {
                ContentUnavailableView("Nothing yet", systemImage: state.selectedAction.icon,
                                       description: Text("Write or paste text on the left, then press ⌘↩.\nTip: select text in any app and press \(state.hotKey.label)."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let e = state.errorMessage { ErrorBanner(message: e).padding(.bottom, 18) }
                        if state.isRunning || !state.raw.isEmpty {   // a bare error shows no empty result block
                            if state.selectedAction.kind == .promptEngineer {
                                PromptReport(r: state.result ?? .empty)
                            } else {
                                OutputBlock(title: state.selectedAction.name, text: state.output, monospaced: false)
                            }
                        }
                        if !state.isRunning && !state.output.isEmpty {
                            SectionRule()
                            RefineBox()
                        }
                    }
                    .padding(20)
                    .motion(layoutKey)
                }
            }
        }
        .background(Theme.groundAlt)
    }

    /// Changes only when a section appears or disappears, so streamed text isn't animated chunk by chunk.
    private var layoutKey: [Bool] {
        let r = state.result ?? .empty
        return [state.isRunning, state.errorMessage == nil, r.diagnosis.isEmpty, r.changes.isEmpty, r.followUps.isEmpty]
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        // Red only on the icon: red body text on a light surface fails WCAG AA.
        Label {
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
    }
}

/// Score first (the signature meter), then the improved prompt, which is what the user came for.
/// Questions follow because answering them re-runs it.
struct PromptReport: View {
    @EnvironmentObject var state: AppState
    let r: ForgeResult

    var body: some View {
        ScoreMeter(before: r.scoreBefore, after: r.scoreAfter, isRunning: state.isRunning)
        SectionRule()
        OutputBlock(title: "Improved prompt", text: r.improvedPrompt, monospaced: true)
        if !r.followUps.isEmpty && !state.isRunning {
            SectionRule()
            QuestionsSection(r: r)
        }
        if !r.diagnosis.isEmpty {
            SectionRule()
            BulletSection(title: "What held it back", items: r.diagnosis)
        }
        if !r.changes.isEmpty {
            SectionRule()
            BulletSection(title: "What changed", items: r.changes)
        }
    }
}

struct OutputBlock: View {
    @EnvironmentObject var state: AppState
    let title: String
    let text: String
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title).font(.headline)
                if state.isRunning && state.selectedAction.kind != .promptEngineer { ProgressView().controlSize(.small) }
                Spacer()
                Button("Use as input") { state.useOutputAsDraft() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.muted)
                    .disabled(text.isEmpty || state.isRunning)
                Button { state.copy(text) } label: {
                    Label(state.justCopied ? "Copied" : "Copy", systemImage: state.justCopied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(text.isEmpty)
            }
            Text(text.isEmpty ? "…" : text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .field()
        }
    }
}

struct RefineBox: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Refine").font(.headline)
            HStack {
                TextField("Refine", text: $state.feedback, prompt: Text(""))
                    .textFieldStyle(.roundedBorder)
                    .placeholder("e.g. “shorter”, “return JSON”, “more formal”", when: state.feedback.isEmpty)
                    .onSubmit { state.refine() }
                Button("Refine") { state.refine() }
                    .disabled(state.feedback.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct BulletSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Image(systemName: "circle.fill")).font(.system(size: 6)).baselineOffset(2)
                        .foregroundStyle(Theme.dot)
                        .accessibilityHidden(true)
                    Text(item).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Assumptions the model made, each correctable (or questions on history items from before assumptions).
struct QuestionsSection: View {
    @EnvironmentObject var state: AppState
    let r: ForgeResult

    private var correcting: Bool { !r.assumptions.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(correcting ? "Assumptions" : "Questions that would sharpen it").font(.headline)
            if correcting {
                Text("The prompt above assumes these. Correct any that are wrong and re-run.")
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            ForEach(r.followUps, id: \.self) { q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q).fixedSize(horizontal: false, vertical: true)
                    TextField(correcting ? "Correction" : "Answer", text: Binding(
                        get: { state.answers[q, default: ""] },
                        set: { state.answers[q] = $0 }), prompt: Text(""))
                        .textFieldStyle(.roundedBorder)
                        .placeholder(correcting ? "Correction (optional)" : "Your answer (optional)",
                                     when: state.answers[q, default: ""].isEmpty)
                        .accessibilityLabel(correcting ? "Correction for: \(q)" : "Answer to: \(q)")
                }
            }
            Button(correcting ? "Re-run with corrections" : "Re-run with answers") { state.submitAnswers() }
                .disabled(state.answers.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}
