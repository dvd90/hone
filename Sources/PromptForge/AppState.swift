import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Input
    @Published var draft = ""
    @Published var goal = ""
    @Published var target: TargetModel { didSet { UserDefaults.standard.set(target.rawValue, forKey: "target") } }
    @Published var depth: Depth { didSet { UserDefaults.standard.set(depth.rawValue, forKey: "depth") } }
    @Published var techniques: Set<Technique> = []
    @Published var selectedActionID = AIAction.improvePrompt.id

    // Output
    @Published var raw = ""
    @Published var result: ForgeResult?
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var feedback = ""
    @Published var answers: [String: String] = [:]
    @Published var justCopied = false

    // History
    @Published var history: [HistoryItem] = []
    @Published var currentID: UUID?

    // Settings
    @Published var providerSettings: ProviderSettings { didSet { providerSettings.save() } }
    @Published var customActions: [AIAction] { didSet { saveJSON(customActions, "customActions") } }
    @Published var hiddenActionIDs: Set<String> { didSet { saveJSON(hiddenActionIDs, "hiddenActionIDs") } }
    @Published var hotKey: HotKeyPreset { didSet { UserDefaults.standard.set(hotKey.rawValue, forKey: "hotKey"); applyHotKey() } }

    let quickPanel = QuickPanelController()
    let serviceProvider = ServiceProvider()
    var openMainWindow: (() -> Void)?

    private var conversation: [ChatMessage] = []
    private var task: Task<Void, Never>?
    private var hotKeyRef: GlobalHotKey?

    private init() {
        let d = UserDefaults.standard
        target = d.string(forKey: "target").flatMap(TargetModel.init(rawValue:)) ?? .claude
        depth = d.string(forKey: "depth").flatMap(Depth.init(rawValue:)) ?? .standard
        providerSettings = ProviderSettings.load()
        customActions = Self.loadJSON("customActions") ?? []
        hiddenActionIDs = Self.loadJSON("hiddenActionIDs") ?? []
        hotKey = d.string(forKey: "hotKey").flatMap(HotKeyPreset.init(rawValue:)) ?? .ctrlOptSpace
        history = HistoryStore.load()
        quickPanel.state = self
    }

    // MARK: Derived

    var allActions: [AIAction] { AIAction.builtIns + customActions }
    var actions: [AIAction] { allActions.filter { !hiddenActionIDs.contains($0.id) } }
    var selectedAction: AIAction { allActions.first { $0.id == selectedActionID } ?? .improvePrompt }
    var promptOptions: PromptOptions { PromptOptions(target: target, depth: depth, techniques: techniques, goal: goal) }
    var output: String { ActionEngine.displayText(action: selectedAction, raw: raw) }

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

    // MARK: Main-window actions

    func run() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        conversation = [ActionEngine.firstMessage(action: selectedAction, text: text, options: promptOptions)]
        currentID = nil
        answers = [:]
        feedback = ""
        execute(rollback: nil)
    }

    func refine() {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(followUp: ActionEngine.followUp(action: selectedAction, feedback: text))
        feedback = ""
    }

    func submitAnswers() {
        let qa = (result?.questions ?? []).compactMap { q -> String? in
            guard let a = answers[q]?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
            return "Q: \(q)\nA: \(a)"
        }
        guard !qa.isEmpty else { return }
        send(followUp: "Here are answers to your questions. Incorporate them and replace any related placeholders. Respond in the same format.\n\n<answers>\n\(qa.joined(separator: "\n\n"))\n</answers>")
        answers = [:]
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clearOutput() {
        cancel()
        raw = ""; result = nil; errorMessage = nil; feedback = ""; answers = [:]; conversation = []; currentID = nil
    }

    func reset() {
        clearOutput()
        draft = ""; goal = ""
    }

    func open(_ item: HistoryItem) {
        cancel()
        selectedActionID = allActions.contains { $0.id == item.actionID } ? item.actionID : AIAction.improvePrompt.id
        draft = item.draft; goal = item.goal; target = item.target
        raw = item.raw; result = item.result; conversation = item.conversation
        currentID = item.id; errorMessage = nil; answers = [:]; feedback = ""
    }

    /// Called by the quick panel's "Open in App".
    func load(action: AIAction, draft text: String, raw r: String) {
        cancel()
        selectedActionID = action.id
        draft = text
        raw = r
        result = action.kind == .promptEngineer ? ForgeResult.parse(r) : nil
        conversation = [ActionEngine.firstMessage(action: action, text: text, options: promptOptions)]
        currentID = history.first { $0.raw == r }?.id
        errorMessage = nil; answers = [:]; feedback = ""
    }

    func delete(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        if currentID == item.id { currentID = nil }
        HistoryStore.save(history)
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

    func useOutputAsDraft() {
        let out = output
        guard !out.isEmpty else { return }
        clearOutput()
        draft = out
    }

    func testConnection() async -> String {
        do {
            let provider = try ProviderFactory.make(providerSettings)
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

    // MARK: Custom actions

    func addCustomAction() -> AIAction {
        let a = AIAction.newCustom()
        customActions.append(a)
        return a
    }

    func updateCustomAction(_ a: AIAction) {
        if let i = customActions.firstIndex(where: { $0.id == a.id }) { customActions[i] = a }
    }

    func deleteCustomAction(_ a: AIAction) {
        customActions.removeAll { $0.id == a.id }
        if selectedActionID == a.id {
            selectedActionID = AIAction.improvePrompt.id
            clearOutput()   // its output would otherwise be shown as a prompt report
        }
    }

    // MARK: History

    @discardableResult
    func recordHistory(action: AIAction, draft text: String, raw r: String, conversation conv: [ChatMessage], id: UUID? = nil) -> UUID {
        let item = HistoryItem(id: id ?? UUID(), date: Date(), actionID: action.id, actionName: action.name,
                               draft: text, goal: action.kind == .promptEngineer ? goal : "", target: target,
                               provider: providerSettings.kind.shortLabel, raw: r, conversation: conv)
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        HistoryStore.save(history)
        return item.id
    }

    // MARK: Engine

    private func send(followUp: String) {
        guard !raw.isEmpty, !conversation.isEmpty, !isRunning else { return }
        let snapshot = (conversation, raw, result)
        conversation.append(ChatMessage(role: "assistant", content: raw))
        conversation.append(ChatMessage(role: "user", content: followUp))
        execute(rollback: snapshot)
    }

    private func execute(rollback: ([ChatMessage], String, ForgeResult?)?) {
        let provider: LLMProvider
        do { provider = try ProviderFactory.make(providerSettings) } catch {
            errorMessage = error.localizedDescription
            if let r = rollback { conversation = r.0 }
            return
        }

        task?.cancel()
        errorMessage = nil
        isRunning = true
        raw = ""
        result = nil

        let action = selectedAction
        let system = ActionEngine.system(for: action)
        let messages = conversation
        task = Task { [weak self] in
            do {
                for try await chunk in provider.stream(system: system, messages: messages, maxTokens: 8000) {
                    guard let self else { return }
                    self.raw += chunk
                    if action.kind == .promptEngineer { self.result = ForgeResult.parse(self.raw) }
                }
                self?.finish(action: action)
            } catch {
                guard let self else { return }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled { self.errorMessage = error.localizedDescription }
                if let r = rollback { self.conversation = r.0; self.raw = r.1; self.result = r.2 }
                self.isRunning = false
            }
        }
    }

    private func finish(action: AIAction) {
        isRunning = false
        if action.kind == .promptEngineer { result = ForgeResult.parse(raw) }
        guard !ActionEngine.displayText(action: action, raw: raw).isEmpty else {
            errorMessage = "The model returned nothing usable. Try again."
            return
        }
        currentID = recordHistory(action: action, draft: draft, raw: raw, conversation: conversation, id: currentID)
    }

    // MARK: Persistence helpers

    private func saveJSON<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}
