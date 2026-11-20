import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            HistorySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            HSplitView {
                InputPane().frame(minWidth: 380, idealWidth: 460)
                OutputPane().frame(minWidth: 440)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { state.reset() } label: { Label("New", systemImage: "square.and.pencil") }
                    .help("New (⌘N)")
            }
        }
        .onAppear { state.openMainWindow = { openWindow(id: "main") } }
        .tint(Theme.accent)
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
                            Text(item.actionName)
                            if let r = item.result, let b = r.scoreBefore, let a = r.scoreAfter { Text("· \(b)→\(a)") }
                            Spacer()
                            Text(item.date.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 2)
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
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 6)]

    private var isPrompt: Bool { state.selectedAction.kind == .promptEngineer }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Action", selection: $state.selectedActionID) {
                    ForEach(state.actions) { a in Label(a.name, systemImage: a.icon).tag(a.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 230)
                Spacer()
                Text("\(state.draft.count) chars").font(.caption).foregroundStyle(Theme.muted)
                Button("Paste") { state.pasteDraft() }.controlSize(.small).capsuleButton()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.draft)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if state.draft.isEmpty {
                    Text(isPrompt ? "Paste or type the prompt you want to improve…" : "Paste or type the text to work on…")
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .field()
            .frame(minHeight: 180)

            if isPrompt { VStack(alignment: .leading, spacing: 12) { promptOptions }.card() }
            else {
                Text(state.selectedAction.instruction)
                    .font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if state.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { state.cancel() }.capsuleButton()
                }
                Text(state.providerSettings.kind.shortLabel).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button { state.run() } label: {
                    Label(isPrompt ? "Improve prompt" : state.selectedAction.name, systemImage: state.selectedAction.icon)
                        .padding(.horizontal, 6)
                }
                .capsuleButton(prominent: true)
                .controlSize(.large)
                .help("⌘↩")
                .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isRunning)
            }
        }
        .padding(16)
        .onChange(of: state.selectedActionID) { state.clearOutput() }
    }

    @ViewBuilder private var promptOptions: some View {
        TextField("Goal / context (optional): who uses it, what a great answer looks like",
                  text: $state.goal, axis: .vertical)
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)

        HStack(spacing: 16) {
            Picker("Target", selection: $state.target) {
                ForEach(TargetModel.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(maxWidth: 210)
            Picker("Depth", selection: $state.depth) {
                ForEach(Depth.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Techniques").font(.subheadline.weight(.semibold))
                Text(state.techniques.isEmpty ? "auto: the engineer picks" : "\(state.techniques.count) required")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if !state.techniques.isEmpty {
                    Button("Clear") { state.techniques.removeAll() }.buttonStyle(.link).controlSize(.small)
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Technique.allCases) { t in
                    Toggle(isOn: Binding(
                        get: { state.techniques.contains(t) },
                        set: { on in if on { state.techniques.insert(t) } else { state.techniques.remove(t) } })) {
                        Label(t.rawValue, systemImage: t.icon).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    .help(t.instruction)
                }
            }
        }
    }
}

// MARK: - Output

struct OutputPane: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.raw.isEmpty && !state.isRunning && state.errorMessage == nil {
            ContentUnavailableView("Nothing yet", systemImage: state.selectedAction.icon,
                                   description: Text("Write or paste text on the left, then press ⌘↩.\nTip: select text in any app and press \(state.hotKey.label)."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let e = state.errorMessage {
                        // Red only on the icon: red body text on a light surface fails WCAG AA.
                        Label { Text(e).textSelection(.enabled) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                        .card(padding: 12)
                    }
                    if state.selectedAction.kind == .promptEngineer {
                        PromptReport(r: state.result ?? .empty)
                    } else {
                        OutputBlock(title: state.selectedAction.name, icon: state.selectedAction.icon,
                                    text: state.output, monospaced: false)
                    }
                    if !state.isRunning && !state.output.isEmpty { RefineBox() }
                }
                .padding(16)
                .animation(Theme.motion, value: layoutKey)
            }
        }
    }

    /// Changes only when a section appears or disappears, so streamed text isn't animated chunk by chunk.
    private var layoutKey: [Bool] {
        let r = state.result ?? .empty
        return [state.isRunning, state.errorMessage == nil, r.diagnosis.isEmpty, r.changes.isEmpty, r.questions.isEmpty]
    }
}

struct PromptReport: View {
    @EnvironmentObject var state: AppState
    let r: ForgeResult

    var body: some View {
        HStack(spacing: 10) {
            ScoreBadge(title: "Before", score: r.scoreBefore)
            Image(systemName: "arrow.right").foregroundStyle(Theme.muted)
            ScoreBadge(title: "After", score: r.scoreAfter)
            Spacer()
            if state.isRunning {
                ProgressView().controlSize(.small)
                Text("Engineering…").foregroundStyle(Theme.muted)
            }
        }
        if !r.diagnosis.isEmpty {
            BulletSection(title: "What held it back", icon: "stethoscope", items: r.diagnosis)
        }
        OutputBlock(title: "Improved prompt", icon: "sparkles", text: r.improvedPrompt, monospaced: true)
        if !r.changes.isEmpty {
            BulletSection(title: "What changed", icon: "list.bullet.clipboard", items: r.changes)
        }
        if !r.questions.isEmpty && !state.isRunning {
            QuestionsSection(questions: r.questions)
        }
    }
}

struct OutputBlock: View {
    @EnvironmentObject var state: AppState
    let title: String
    let icon: String
    let text: String
    let monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                if state.isRunning && state.selectedAction.kind != .promptEngineer { ProgressView().controlSize(.small) }
                Spacer()
                Button("Use as input") { state.useOutputAsDraft() }
                    .capsuleButton()
                    .disabled(text.isEmpty || state.isRunning)
                Button { state.copy(text) } label: {
                    Label(state.justCopied ? "Copied" : "Copy", systemImage: state.justCopied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .capsuleButton(prominent: true)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(text.isEmpty)
            }
            Text(text.isEmpty ? "…" : text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .field()
        }
        .card()
    }
}

struct RefineBox: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Refine", systemImage: "slider.horizontal.3").font(.headline)
            HStack {
                TextField("e.g. “shorter”, “return JSON”, “more formal”", text: $state.feedback)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.refine() }
                Button("Refine") { state.refine() }
                    .capsuleButton()
                    .disabled(state.feedback.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .card()
    }
}

struct ScoreBadge: View {
    let title: String
    let score: Int?

    private var color: Color {
        guard let s = score else { return .clear }
        return s < 50 ? .red : s < 75 ? .orange : .green
    }

    // The number stays in the primary color (orange/green text fails WCAG AA); a status dot carries the color.
    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(score.map(String.init) ?? "—").font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Text(title).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(width: 76, height: 52)
        .glass(in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
        .animation(Theme.motion, value: score)
    }
}

struct BulletSection: View {
    let title: String
    let icon: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(Theme.muted)
                    Text(item).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}

struct QuestionsSection: View {
    @EnvironmentObject var state: AppState
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Questions that would sharpen it", systemImage: "questionmark.bubble").font(.headline)
            ForEach(questions, id: \.self) { q in
                VStack(alignment: .leading, spacing: 4) {
                    Text(q).fixedSize(horizontal: false, vertical: true)
                    TextField("Your answer (optional)", text: Binding(
                        get: { state.answers[q, default: ""] },
                        set: { state.answers[q] = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }
            Button("Re-run with answers") { state.submitAnswers() }
                .capsuleButton(prominent: true)
                .disabled(state.answers.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        .card()
    }
}
