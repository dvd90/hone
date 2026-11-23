import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Input
    @Published var draft = ""
    /// Per-run context for Improve Prompt (stored in HistoryItem.goal).
    @Published var notes = ""
    @Published var attachments: [Attachment] = []
    /// Obsidian notes for the next main-window run, refreshed as the draft changes; shown as removable chips.
    @Published var vaultNotes: [Attachment] = []
    /// The app and window an "Open in App" run came from; empty for runs started in the main window.
    @Published var sourceApp = ""
    @Published var target: TargetModel { didSet { defaults.set(target.rawValue, forKey: "target") } }
    @Published var depth: Depth { didSet { defaults.set(depth.rawValue, forKey: "depth") } }
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
    @Published var providerSettings: ProviderSettings { didSet { providerSettings.save(to: defaults) } }
    @Published var customActions: [AIAction] { didSet { saveJSON(customActions, "customActions") } }
    @Published var hiddenActionIDs: Set<String> { didSet { saveJSON(hiddenActionIDs, "hiddenActionIDs") } }
    @Published var hotKey: HotKeyPreset { didSet { defaults.set(hotKey.rawValue, forKey: "hotKey"); applyHotKey() } }
    @Published var contextProfiles: [ContextProfile] { didSet { saveJSON(contextProfiles, "contextProfiles.v1") } }
    /// The profile used for Improve Prompt, in the main window and the quick panel alike; nil = none.
    @Published var contextProfileID: UUID? { didSet { defaults.set(contextProfileID?.uuidString, forKey: "contextProfileID") } }
    /// Whether the hotkey adds the app and window title the user came from.
    @Published var includeSourceApp: Bool { didSet { defaults.set(includeSourceApp, forKey: "includeSourceApp") } }
    /// The Obsidian vault folder Improve Prompt may take notes from; empty = off.
    @Published var obsidianVault: String { didSet { defaults.set(obsidianVault, forKey: "obsidianVault") } }
    /// Share of the draft's distinctive words an unlinked note must cover (a title match adds a bonus); lower adds more notes.
    @Published var obsidianMinScore: Double { didSet { defaults.set(obsidianMinScore, forKey: "obsidianMinScore") } }
    static let defaultMinScore = 1.0

    let quickPanel = QuickPanelController()
    let serviceProvider = ServiceProvider()
    var openMainWindow: (() -> Void)?

    private(set) var conversation: [ChatMessage] = []
    private var task: Task<Void, Never>?
    private var vaultIndex: VaultIndex?
    /// Vault notes the user removed from this draft; they stay out until the draft is reset.
    private var removedVaultNotes: Set<String> = []
    var hotKeyRef: GlobalHotKey?   // owned by the glue in AppState+System.swift

    let defaults: UserDefaults
    let historyURL: URL
    let makeProvider: (ProviderSettings) throws -> LLMProvider

    /// Tests inject a scratch defaults suite, a temp history file and a fake provider.
    init(defaults: UserDefaults = .standard, historyURL: URL = HistoryStore.url,
         makeProvider: @escaping (ProviderSettings) throws -> LLMProvider = { try ProviderFactory.make($0) }) {
        self.defaults = defaults
        self.historyURL = historyURL
        self.makeProvider = makeProvider
        target = defaults.string(forKey: "target").flatMap(TargetModel.init(rawValue:)) ?? .claude
        depth = defaults.string(forKey: "depth").flatMap(Depth.init(rawValue:)) ?? .standard
        providerSettings = ProviderSettings.load(from: defaults)
        customActions = Self.loadJSON("customActions", from: defaults) ?? []
        hiddenActionIDs = Self.loadJSON("hiddenActionIDs", from: defaults) ?? []
        hotKey = defaults.string(forKey: "hotKey").flatMap(HotKeyPreset.init(rawValue:)) ?? .ctrlOptSpace
        contextProfiles = Self.loadJSON("contextProfiles.v1", from: defaults) ?? []
        contextProfileID = defaults.string(forKey: "contextProfileID").flatMap(UUID.init(uuidString:))
        includeSourceApp = defaults.object(forKey: "includeSourceApp") as? Bool ?? true
        obsidianVault = defaults.string(forKey: "obsidianVault") ?? ""
        obsidianMinScore = defaults.object(forKey: "obsidianMinScore") as? Double ?? Self.defaultMinScore
        history = HistoryStore.load(from: historyURL)
        quickPanel.state = self
    }

    // MARK: Derived

    var allActions: [AIAction] { AIAction.builtIns + customActions }
    var actions: [AIAction] { allActions.filter { !hiddenActionIDs.contains($0.id) } }
    var selectedAction: AIAction { allActions.first { $0.id == selectedActionID } ?? .improvePrompt }
    var selectedProfile: ContextProfile? { contextProfiles.first { $0.id == contextProfileID } }

    /// Main-window runs: profile, notes, attached files, vault notes, and the source app when the run came from the panel.
    var promptOptions: PromptOptions {
        PromptOptions(target: target, depth: depth, techniques: techniques,
                      context: PromptContext(profile: selectedProfile, notes: notes, source: sourceApp, files: attachments,
                                             vaultNotes: vaultNotes))
    }

    /// Quick-panel runs: the profile, where the user came from and the panel's own vault notes,
    /// never the main window's notes or files.
    func panelOptions(source: String, vaultNotes panelNotes: [Attachment] = []) -> PromptOptions {
        PromptOptions(target: target, depth: depth, techniques: techniques,
                      context: PromptContext(profile: selectedProfile, source: source, vaultNotes: panelNotes))
    }
    var output: String { ActionEngine.displayText(action: selectedAction, raw: raw) }

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

    /// Sends the author's corrections to listed assumptions (or answers to questions on older history items).
    func submitAnswers() {
        guard let result else { return }
        let correcting = !result.assumptions.isEmpty
        let pairs = result.followUps.compactMap { item -> String? in
            guard let a = answers[item]?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
            return correcting ? "Assumed: \(item)\nActually: \(a)" : "Q: \(item)\nA: \(a)"
        }
        guard !pairs.isEmpty else { return }
        let body = pairs.joined(separator: "\n\n")
        send(followUp: correcting
            ? "The author reviewed your assumptions. Apply these corrections everywhere they matter, keep only assumptions that still stand, and respond in the same format.\n\n<corrections>\n\(body)\n</corrections>"
            : "Here are answers to your questions. Incorporate them and replace any related placeholders. Respond in the same format.\n\n<answers>\n\(body)\n</answers>")
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
        draft = ""; notes = ""; attachments = []; sourceApp = ""; clearVaultNotes()
    }

    func open(_ item: HistoryItem) {
        cancel()
        selectedActionID = allActions.contains { $0.id == item.actionID } ? item.actionID : AIAction.improvePrompt.id
        draft = item.draft; notes = item.goal; target = item.target
        attachments = []; sourceApp = ""; clearVaultNotes()
        raw = item.raw; result = item.result
        // Older quick-panel items saved [user, assistant]; follow-ups append the reply themselves.
        conversation = item.conversation.last?.role == "assistant" ? Array(item.conversation.dropLast()) : item.conversation
        currentID = item.id; errorMessage = nil; answers = [:]; feedback = ""
    }

    /// Called by the quick panel's "Open in App", with the message the panel actually sent.
    func load(action: AIAction, draft text: String, raw r: String, message: ChatMessage, source: String) {
        cancel()
        selectedActionID = action.id
        draft = text
        notes = ""; attachments = []; sourceApp = source; clearVaultNotes()
        raw = r
        result = action.kind == .promptEngineer ? ForgeResult.parse(r) : nil
        conversation = [message]
        currentID = history.first { $0.raw == r }?.id
        errorMessage = nil; answers = [:]; feedback = ""
    }

    func delete(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        if currentID == item.id { currentID = nil }
        HistoryStore.save(history, to: historyURL)
    }

    func useOutputAsDraft() {
        let out = output
        guard !out.isEmpty else { return }
        clearOutput()
        draft = out
    }

    // MARK: Context

    /// Adds text files to the next run, enforcing the per-file and total caps; problems show in the error banner.
    func attach(_ urls: [URL]) {
        var problems: [String] = []
        for url in urls {
            do {
                let file = try Attachment.read(url)
                if attachments.contains(where: { $0.name == file.name && $0.text == file.text }) { continue }
                let total = attachments.reduce(0) { $0 + $1.text.utf8.count } + file.text.utf8.count
                guard total <= Attachment.maxTotalBytes else { throw Attachment.ReadError.overTotal(file.name) }
                attachments.append(file)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    func removeAttachment(_ file: Attachment) {
        attachments.removeAll { $0.id == file.id }
    }

    /// Vault notes worth sending with this text: the note open in Obsidian (from `source`), notes linked with
    /// `[[Note]]` in the profile, run notes or text, then the best matches for the text and run notes.
    func relevantNotes(text: String, notes runNotes: String, source: String) async -> [Attachment] {
        guard !obsidianVault.isEmpty else { return [] }
        let root = URL(fileURLWithPath: obsidianVault, isDirectory: true)
        let index = vaultIndex.flatMap { $0.root == root ? $0 : nil } ?? VaultIndex(root: root)
        vaultIndex = index
        return await index.pick(open: Obsidian.openNote(source: source, vault: root.lastPathComponent),
                                links: Obsidian.links(in: [selectedProfile?.text ?? "", runNotes, text].joined(separator: "\n")),
                                query: text + "\n" + runNotes, minScore: obsidianMinScore)
    }

    /// Recomputes the main window's vault notes; a superseded refresh (the draft changed meanwhile) is dropped.
    func refreshVaultNotes() async {
        let found = await relevantNotes(text: draft, notes: notes, source: sourceApp)
        guard !Task.isCancelled else { return }
        vaultNotes = found.filter { !removedVaultNotes.contains($0.name) }
    }

    func removeVaultNote(_ note: Attachment) {
        removedVaultNotes.insert(note.name)
        vaultNotes.removeAll { $0.name == note.name }
    }

    private func clearVaultNotes() {
        vaultNotes = []; removedVaultNotes = []
    }

    func addProfile() -> ContextProfile {
        let p = ContextProfile()
        contextProfiles.append(p)
        if contextProfileID == nil { contextProfileID = p.id }
        return p
    }

    func updateProfile(_ p: ContextProfile) {
        if let i = contextProfiles.firstIndex(where: { $0.id == p.id }) { contextProfiles[i] = p }
    }

    func deleteProfile(_ p: ContextProfile) {
        contextProfiles.removeAll { $0.id == p.id }
        if contextProfileID == p.id { contextProfileID = nil }
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
    func recordHistory(action: AIAction, draft text: String, raw r: String, conversation conv: [ChatMessage],
                       id: UUID? = nil, notes runNotes: String? = nil) -> UUID {
        let kept = action.kind == .promptEngineer ? (runNotes ?? notes) : ""
        let item = HistoryItem(id: id ?? UUID(), date: Date(), actionID: action.id, actionName: action.name,
                               draft: text, goal: kept, target: target,
                               provider: providerSettings.kind.shortLabel, raw: r, conversation: conv.map(Obsidian.redacted))
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        HistoryStore.save(history, to: historyURL)
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
        do { provider = try makeProvider(providerSettings) } catch {
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
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}
