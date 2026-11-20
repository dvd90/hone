import AppKit
import SwiftUI

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
                            Text(item.actionName).lineLimit(1)
                            if let r = item.result, let b = r.scoreBefore, let a = r.scoreAfter {
                                Text("· \(b)→\(a)").monospacedDigit().fixedSize()
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
        VStack(alignment: .leading, spacing: 14) {
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
            .field()
            .frame(minHeight: 160, maxHeight: .infinity)

            if isPrompt { promptOptions }
            else {
                Text(state.selectedAction.instruction)
                    .font(.callout).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var promptOptions: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Goal").gridColumnAlignment(.trailing)
                TextField("Optional: who it's for, what good looks like", text: $state.goal, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Target")
                Picker("Target", selection: $state.target) {
                    ForEach(TargetModel.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            GridRow {
                Text("Depth")
                Picker("Depth", selection: $state.depth) {
                    ForEach(Depth.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Techniques")
                Text(state.techniques.isEmpty ? "Auto: the engineer picks" : "\(state.techniques.count) required")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if !state.techniques.isEmpty {
                    Button("Clear") { state.techniques.removeAll() }.buttonStyle(.link).controlSize(.small)
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

    static func arrange(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in sizes {
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + s.width)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - Output

struct OutputPane: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.raw.isEmpty && !state.isRunning && state.errorMessage == nil {
            ContentUnavailableView("Nothing yet", systemImage: state.selectedAction.icon,
                                   description: Text("Write or paste text on the left, then press ⌘↩.\nTip: select text in any app and press \(state.hotKey.label)."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let e = state.errorMessage { ErrorBanner(message: e) }
                    if state.isRunning || !state.raw.isEmpty {   // a bare error shows no empty result block
                        if state.selectedAction.kind == .promptEngineer {
                            PromptReport(r: state.result ?? .empty)
                        } else {
                            OutputBlock(title: state.selectedAction.name, icon: state.selectedAction.icon,
                                        text: state.output, monospaced: false)
                        }
                    }
                    if !state.isRunning && !state.output.isEmpty { RefineBox() }
                }
                .padding(20)
                .motion(layoutKey)
            }
        }
    }

    /// Changes only when a section appears or disappears, so streamed text isn't animated chunk by chunk.
    private var layoutKey: [Bool] {
        let r = state.result ?? .empty
        return [state.isRunning, state.errorMessage == nil, r.diagnosis.isEmpty, r.changes.isEmpty, r.questions.isEmpty]
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

/// The improved prompt leads: it is what the user came for. Questions follow because answering them re-runs it.
struct PromptReport: View {
    @EnvironmentObject var state: AppState
    let r: ForgeResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            ScoreBadge(title: "Before", score: r.scoreBefore)
            Text(Image(systemName: "arrow.right")).font(.title3).foregroundStyle(Theme.muted)
            ScoreBadge(title: "After", score: r.scoreAfter)
            Spacer()
            if state.isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Engineering…").foregroundStyle(Theme.muted)
                }
            }
        }
        OutputBlock(title: "Improved prompt", icon: "sparkles", text: r.improvedPrompt, monospaced: true)
        if !r.questions.isEmpty && !state.isRunning {
            QuestionsSection(questions: r.questions)
        }
        if !r.diagnosis.isEmpty {
            BulletSection(title: "What held it back", icon: "stethoscope", items: r.diagnosis)
        }
        if !r.changes.isEmpty {
            BulletSection(title: "What changed", icon: "list.bullet.clipboard", items: r.changes)
        }
    }
}

struct SectionTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(Theme.muted) }
            .font(.headline)
    }
}

struct OutputBlock: View {
    @EnvironmentObject var state: AppState
    let title: String
    let icon: String
    let text: String
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionTitle(title: title, icon: icon)
                if state.isRunning && state.selectedAction.kind != .promptEngineer { ProgressView().controlSize(.small) }
                Spacer()
                Button("Use as input") { state.useOutputAsDraft() }
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
            SectionTitle(title: "Refine", icon: "slider.horizontal.3")
            HStack {
                TextField("e.g. “shorter”, “return JSON”, “more formal”", text: $state.feedback)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.refine() }
                Button("Refine") { state.refine() }
                    .disabled(state.feedback.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct ScoreBadge: View {
    let title: String
    let score: Int?

    private var color: Color {
        guard let s = score else { return Color.primary.opacity(0.2) }
        return s < 50 ? .red : s < 75 ? .orange : .green
    }

    // The number stays in the primary color (orange/green text fails WCAG AA); a status dot carries the color.
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(score.map(String.init) ?? "–").font(.title.weight(.semibold).monospacedDigit())
             + Text(" /100").font(.callout).foregroundStyle(Theme.muted))
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .motion(score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) score")
        .accessibilityValue(score.map { "\($0) out of 100" } ?? "Pending")
    }
}

struct BulletSection: View {
    let title: String
    let icon: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: title, icon: icon)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Theme.muted)
                    Text(item).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct QuestionsSection: View {
    @EnvironmentObject var state: AppState
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Questions that would sharpen it", icon: "questionmark.bubble")
            ForEach(questions, id: \.self) { q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q).fixedSize(horizontal: false, vertical: true)
                    TextField("Your answer (optional)", text: Binding(
                        get: { state.answers[q, default: ""] },
                        set: { state.answers[q] = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }
            Button("Re-run with answers") { state.submitAnswers() }
                .disabled(state.answers.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}
