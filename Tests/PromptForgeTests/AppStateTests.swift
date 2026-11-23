import XCTest
@testable import PromptForge

/// AppState logic with a fake provider, a scratch UserDefaults suite and a temp history file,
/// so nothing touches the user's real settings, history, Keychain or a live model.
@MainActor
final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var historyURL: URL!
    private var calls: [[ChatMessage]] = []
    /// What the next provider call streams; nil = fail to create the provider.
    private var replies: [Reply] = []

    enum Reply {
        case text([String])
        case failure(Error)
        case hang
        case noProvider
    }

    override func setUp() async throws {
        suiteName = "PF-appstate-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("PF-history-\(UUID().uuidString).json")
        calls = []
        replies = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: historyURL)
    }

    private func makeState() -> AppState {
        AppState(defaults: defaults, historyURL: historyURL) { [unowned self] _ in
            let reply = replies.isEmpty ? .text(["ok"]) : replies.removeFirst()
            if case .noProvider = reply { throw ForgeError.config("No provider configured.") }
            return FakeProvider(reply: reply) { [unowned self] in calls.append($0) }
        }
    }

    private func settle(_ state: AppState) async {
        for _ in 0..<200 where state.isRunning { try? await Task.sleep(for: .milliseconds(5)) }
        await Task.yield()
    }

    private let report = """
    <score_before>30</score_before>
    <diagnosis>
    - vague
    </diagnosis>
    <improved_prompt>
    Write tests for Hone.
    </improved_prompt>
    <changes>
    - added scope
    </changes>
    <questions>
    - Which framework?
    - Which files?
    </questions>
    <score_after>80</score_after>
    """

    // MARK: Startup and persistence

    func testDefaultsWhenNothingIsSaved() {
        let s = makeState()
        XCTAssertEqual(s.target, .claude)
        XCTAssertEqual(s.depth, .standard)
        XCTAssertEqual(s.hotKey, .ctrlOptSpace)
        XCTAssertEqual(s.providerSettings, ProviderSettings())
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertTrue(s.customActions.isEmpty)
        XCTAssertIdentical(s.quickPanel.state, s)
    }

    func testSettingsRoundTripThroughDefaults() {
        let s = makeState()
        s.target = .gpt
        s.depth = .light
        var p = ProviderSettings(); p.kind = .codex
        s.providerSettings = p
        let custom = s.addCustomAction()
        s.hiddenActionIDs = ["proofread"]

        let reloaded = makeState()
        XCTAssertEqual(reloaded.target, .gpt)
        XCTAssertEqual(reloaded.depth, .light)
        XCTAssertEqual(reloaded.providerSettings.kind, .codex)
        XCTAssertEqual(reloaded.customActions.map(\.id), [custom.id])
        XCTAssertEqual(reloaded.hiddenActionIDs, ["proofread"])
        defaults.set("off", forKey: "hotKey")
        XCTAssertEqual(makeState().hotKey, .off)
    }

    func testDerivedActions() {
        let s = makeState()
        XCTAssertEqual(s.allActions.count, AIAction.builtIns.count)
        s.hiddenActionIDs = ["proofread"]
        XCTAssertFalse(s.actions.contains { $0.id == "proofread" })
        s.selectedActionID = "does-not-exist"
        XCTAssertEqual(s.selectedAction, .improvePrompt)
        s.notes = "for devs"
        XCTAssertEqual(s.promptOptions.context.notes, "for devs")
    }

    // MARK: Running

    func testRunImprovePromptRecordsHistory() async {
        replies = [.text([String(report.prefix(40)), String(report.dropFirst(40))])]
        let s = makeState()
        s.draft = "  write tests  "
        s.run()
        await settle(s)
        XCTAssertNil(s.errorMessage)
        XCTAssertEqual(s.result?.improvedPrompt, "Write tests for Hone.")
        XCTAssertEqual(s.output, "Write tests for Hone.")
        XCTAssertEqual(s.history.count, 1)
        XCTAssertEqual(s.currentID, s.history.first?.id)
        XCTAssertEqual(HistoryStore.load(from: historyURL).count, 1)
        XCTAssertTrue(calls.first?.first?.content.contains("<draft_prompt>\nwrite tests\n</draft_prompt>") == true)
    }

    func testRunTransformAndGuards() async {
        let s = makeState()
        s.run()                                  // empty draft: nothing happens
        XCTAssertTrue(calls.isEmpty)
        s.selectedActionID = "proofread"
        s.draft = "teh cat"
        replies = [.text(["  the cat \n"])]
        s.run()
        await settle(s)
        XCTAssertNil(s.result)
        XCTAssertEqual(s.output, "the cat")
        XCTAssertEqual(s.history.first?.goal, "")   // notes are only kept for Improve Prompt
    }

    func testEmptyReplyIsAnErrorAndNotSaved() async {
        replies = [.text(["   "])]
        let s = makeState()
        s.draft = "x"
        s.run()
        await settle(s)
        XCTAssertEqual(s.errorMessage, "The model returned nothing usable. Try again.")
        XCTAssertTrue(s.history.isEmpty)
    }

    func testProviderSetupAndStreamFailures() async {
        replies = [.noProvider, .failure(ForgeError.network("offline")), .failure(CancellationError())]
        let s = makeState()
        s.draft = "x"
        s.run()
        XCTAssertEqual(s.errorMessage, "No provider configured.")
        XCTAssertFalse(s.isRunning)
        s.run()
        await settle(s)
        XCTAssertEqual(s.errorMessage, "offline")
        s.run()
        await settle(s)
        XCTAssertNil(s.errorMessage)              // cancellation isn't reported as an error
    }

    func testCancelStopsARun() async {
        replies = [.hang]
        let s = makeState()
        s.draft = "x"
        s.run()
        XCTAssertTrue(s.isRunning)
        s.run()                                   // ignored while running
        XCTAssertEqual(calls.count, 0)
        s.cancel()
        XCTAssertFalse(s.isRunning)
    }

    // MARK: Follow-ups

    func testRefineAppendsTheConversationAndKeepsTheHistoryItem() async {
        replies = [.text([report]), .text([report.replacingOccurrences(of: "Write tests for Hone.", with: "Shorter.")])]
        let s = makeState()
        s.draft = "write tests"
        s.run()
        await settle(s)
        let id = s.currentID
        s.feedback = "   "
        s.refine()                                // blank feedback: nothing sent
        s.feedback = "shorter"
        s.refine()
        await settle(s)
        XCTAssertEqual(s.output, "Shorter.")
        XCTAssertEqual(s.currentID, id)
        XCTAssertEqual(s.history.count, 1)
        XCTAssertEqual(calls.last?.map(\.role), ["user", "assistant", "user"])
        XCTAssertTrue(calls.last?.last?.content.contains("<feedback>\nshorter\n</feedback>") == true)
        XCTAssertEqual(s.feedback, "")
    }

    func testFailedFollowUpRollsBack() async {
        replies = [.text([report]), .failure(ForgeError.network("offline")), .noProvider]
        let s = makeState()
        s.draft = "write tests"
        s.run()
        await settle(s)
        let before = (s.raw, s.conversation)
        s.feedback = "shorter"
        s.refine()
        await settle(s)
        XCTAssertEqual(s.errorMessage, "offline")
        XCTAssertEqual(s.raw, before.0)
        XCTAssertEqual(s.conversation, before.1)
        s.feedback = "again"
        s.refine()
        XCTAssertEqual(s.errorMessage, "No provider configured.")
        XCTAssertEqual(s.conversation, before.1)
    }

    func testSubmitAnswersSendsOnlyAnsweredQuestions() async {
        replies = [.text([report]), .text([report])]
        let s = makeState()
        s.draft = "write tests"
        s.run()
        await settle(s)
        s.submitAnswers()                         // nothing answered: nothing sent
        XCTAssertEqual(calls.count, 1)
        s.answers = ["Which framework?": " XCTest ", "Which files?": "  "]
        s.submitAnswers()
        await settle(s)
        let sent = calls.last?.last?.content ?? ""
        XCTAssertTrue(sent.contains("Q: Which framework?\nA: XCTest"))
        XCTAssertFalse(sent.contains("Which files?"))
        XCTAssertTrue(s.answers.isEmpty)
    }

    func testFollowUpNeedsAPreviousResult() {
        let s = makeState()
        s.feedback = "shorter"
        s.refine()
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: Opening, loading, clearing

    func testOpenAndLoadKeepTheResult() async {
        replies = [.text([report])]
        let s = makeState()
        s.selectedActionID = "summarize"
        s.draft = "write tests"
        s.notes = "devs"
        s.selectedActionID = AIAction.improvePrompt.id
        s.run()
        await settle(s)
        let item = s.history[0]

        s.reset()
        XCTAssertEqual(s.draft, ""); XCTAssertEqual(s.notes, ""); XCTAssertEqual(s.raw, "")
        s.selectedActionID = "summarize"         // a different action is selected when reopening
        s.open(item)
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)
        XCTAssertEqual(s.output, "Write tests for Hone.")
        XCTAssertEqual(s.notes, "devs")
        XCTAssertEqual(s.currentID, item.id)

        var orphan = item
        orphan.actionID = "deleted-custom-action"
        s.open(orphan)
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)

        s.clearOutput()
        let sent = ChatMessage(role: "user", content: "what the panel sent")
        s.load(action: .improvePrompt, draft: "write tests", raw: item.raw, message: sent, source: "Xcode — App.swift")
        XCTAssertEqual(s.result?.improvedPrompt, "Write tests for Hone.")
        XCTAssertEqual(s.currentID, item.id)
        XCTAssertEqual(s.conversation, [sent])          // follow-ups continue what was actually sent
        XCTAssertEqual(s.sourceApp, "Xcode — App.swift")
        XCTAssertEqual(s.notes, "")
        let proofread = AIAction.builtIns.first { $0.id == "proofread" }!
        s.load(action: proofread, draft: "teh", raw: "the", message: sent, source: "")
        XCTAssertNil(s.result)
        XCTAssertNil(s.currentID)
    }

    func testDeleteAndUseOutputAsDraft() async {
        replies = [.text([report])]
        let s = makeState()
        s.useOutputAsDraft()                      // no output yet: nothing changes
        XCTAssertEqual(s.draft, "")
        s.draft = "write tests"
        s.run()
        await settle(s)
        s.useOutputAsDraft()
        XCTAssertEqual(s.draft, "Write tests for Hone.")
        XCTAssertEqual(s.raw, "")

        s.delete(s.history[0])
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertNil(s.currentID)
        XCTAssertTrue(HistoryStore.load(from: historyURL).isEmpty)
    }

    func testHistoryKeepsTheLatest300() {
        let s = makeState()
        for i in 0..<302 { s.recordHistory(action: .improvePrompt, draft: "d\(i)", raw: "r", conversation: []) }
        XCTAssertEqual(s.history.count, 300)
        XCTAssertEqual(s.history.first?.draft, "d301")
        let id = s.history[5].id
        s.recordHistory(action: .improvePrompt, draft: "updated", raw: "r", conversation: [], id: id)
        XCTAssertEqual(s.history.first?.id, id)
        XCTAssertEqual(s.history.count, 300)
    }

    // MARK: Custom actions

    func testCustomActionCRUD() async {
        let s = makeState()
        var a = s.addCustomAction()
        a.name = "Tweet"
        s.updateCustomAction(a)
        XCTAssertEqual(s.customActions.first?.name, "Tweet")
        s.updateCustomAction(AIAction.newCustom())   // unknown id: ignored
        XCTAssertEqual(s.customActions.count, 1)

        replies = [.text(["done"])]
        s.selectedActionID = a.id
        s.draft = "x"
        s.run()
        await settle(s)
        XCTAssertEqual(s.output, "done")
        s.deleteCustomAction(a)
        XCTAssertTrue(s.customActions.isEmpty)
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)
        XCTAssertEqual(s.raw, "")                 // its output isn't left behind as a prompt report

        let other = s.addCustomAction()
        s.deleteCustomAction(other)               // not selected: selection untouched
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)
    }

    // MARK: Context

    private func textFile(_ name: String, bytes: Int, fill: UInt8 = 0x61) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PF-\(UUID().uuidString)-\(name)")
        try Data(repeating: fill, count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testProfilesAreSavedAndShared() {
        let s = makeState()
        XCTAssertTrue(s.includeSourceApp)                 // on by default
        XCTAssertNil(s.selectedProfile)
        var hone = s.addProfile()                         // the first profile becomes the selection
        XCTAssertEqual(s.contextProfileID, hone.id)
        hone.name = "Hone"; hone.text = "macOS SwiftUI app"
        s.updateProfile(hone)
        s.updateProfile(ContextProfile())                 // unknown id: ignored
        let other = s.addProfile()
        XCTAssertEqual(s.contextProfileID, hone.id)       // adding more doesn't change the selection
        s.includeSourceApp = false

        let reloaded = makeState()
        XCTAssertEqual(reloaded.contextProfiles.map(\.name), ["Hone", "New profile"])
        XCTAssertEqual(reloaded.selectedProfile?.text, "macOS SwiftUI app")
        XCTAssertFalse(reloaded.includeSourceApp)

        s.deleteProfile(other)
        XCTAssertEqual(s.contextProfileID, hone.id)
        s.deleteProfile(hone)                             // deleting the selected one clears the selection
        XCTAssertNil(s.contextProfileID)
        XCTAssertNil(makeState().contextProfileID)
    }

    func testMainWindowSendsAllContextAndThePanelOnlyItsOwn() async throws {
        let s = makeState()
        var profile = s.addProfile(); profile.text = "Hone, a macOS app"; s.updateProfile(profile)
        s.notes = "audience: contributors"
        s.attach([try textFile("CLAUDE.md", bytes: 10)])

        let main = s.promptOptions.context
        XCTAssertEqual(main.profile?.text, "Hone, a macOS app")
        XCTAssertEqual(main.notes, "audience: contributors")
        XCTAssertEqual(main.files.count, 1)

        let panel = s.panelOptions(source: "Xcode — App.swift").context
        XCTAssertEqual(panel.profile?.text, "Hone, a macOS app")
        XCTAssertEqual(panel.source, "Xcode — App.swift")
        XCTAssertEqual(panel.notes, "")                   // main-window notes never leak into panel runs
        XCTAssertTrue(panel.files.isEmpty)

        replies = [.text(["<improved_prompt>\nX\n</improved_prompt>"])]
        s.draft = "write tests"
        s.run()
        await settle(s)
        let sent = calls.first?.first?.content ?? ""
        XCTAssertTrue(sent.contains("<notes>\naudience: contributors\n</notes>"))
        XCTAssertTrue(sent.contains("-CLAUDE.md\">\naaaaaaaaaa\n</file>"))
        XCTAssertEqual(s.history.first?.goal, "audience: contributors")

        s.recordHistory(action: .improvePrompt, draft: "panel run", raw: "r", conversation: [], notes: "")
        XCTAssertEqual(s.history.first?.goal, "")         // panel runs save no main-window notes
    }

    func testAttachEnforcesLimitsAndSkipsDuplicates() throws {
        let s = makeState()
        let a = try textFile("a.txt", bytes: 40_000)
        s.attach([a, a])                                  // same file twice: attached once
        XCTAssertEqual(s.attachments.count, 1)
        XCTAssertNil(s.errorMessage)
        s.attach([try textFile("b.txt", bytes: 40_000, fill: 0x62), try textFile("c.txt", bytes: 40_000, fill: 0x63),
                  try textFile("bin.dat", bytes: 10, fill: 0xFF)])
        XCTAssertEqual(s.attachments.count, 2)            // c.txt would pass 100 KB; bin.dat isn't text
        let problems = try XCTUnwrap(s.errorMessage)
        XCTAssertTrue(problems.contains("100 KB total"))
        XCTAssertTrue(problems.contains("isn't a text file"))

        s.removeAttachment(s.attachments[0])
        XCTAssertEqual(s.attachments.count, 1)
        s.attach([])
        XCTAssertNil(s.errorMessage)
    }

    func testOpenResetAndPanelItemsCleanUpContext() async {
        let s = makeState()
        s.notes = "n"; s.sourceApp = "Xcode"
        s.attachments = [Attachment(name: "f", text: "t")]
        s.reset()
        XCTAssertEqual(s.notes, ""); XCTAssertEqual(s.sourceApp, ""); XCTAssertTrue(s.attachments.isEmpty)

        // An older quick-panel item saved [user, assistant]; reopening drops the assistant turn so a
        // follow-up doesn't send two replies in a row.
        let user = ChatMessage(role: "user", content: "draft"), reply = ChatMessage(role: "assistant", content: "out")
        let item = HistoryItem(id: UUID(), date: Date(), actionID: "proofread", actionName: "Proofread", draft: "draft",
                               goal: "", target: .claude, provider: "Codex", raw: "out", conversation: [user, reply])
        s.attachments = [Attachment(name: "f", text: "t")]
        s.open(item)
        XCTAssertEqual(s.conversation, [user])
        XCTAssertTrue(s.attachments.isEmpty)
        replies = [.text(["shorter"])]
        s.feedback = "shorter"
        s.refine()
        await settle(s)
        XCTAssertEqual(calls.last?.map(\.role), ["user", "assistant", "user"])
    }

    // MARK: Obsidian

    /// A temp vault folder named "Work", removed after the test.
    private func vault(_ notes: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PF-vault-\(UUID().uuidString)/Work")
        for (path, text) in notes {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        return root
    }

    func testVaultSettingsPersist() {
        let s = makeState()
        XCTAssertEqual(s.obsidianVault, "")                 // off by default
        XCTAssertEqual(s.obsidianMinScore, AppState.defaultMinScore)
        s.obsidianVault = "/tmp/Work"; s.obsidianMinScore = 4
        let reloaded = makeState()
        XCTAssertEqual(reloaded.obsidianVault, "/tmp/Work")
        XCTAssertEqual(reloaded.obsidianMinScore, 4)
    }

    func testVaultNotesFollowTheDraftReachTheModelAndStayOutOfHistory() async throws {
        let root = try vault(["Hone.md": "Hone: SwiftUI app, XCTest tests, quick panel.", "Pasta.md": "Boil water.",
                              "Roadmap.md": "Ship Obsidian context."])
        let s = makeState()
        s.draft = "Write XCTest tests for the Hone quick panel"
        await s.refreshVaultNotes()
        XCTAssertEqual(s.vaultNotes, [])                    // nothing until a vault is chosen
        s.obsidianVault = root.path
        var profile = s.addProfile(); profile.text = "Plans live in [[Roadmap]]."; s.updateProfile(profile)
        s.sourceApp = "Obsidian — Pasta - Work - Obsidian v1.7.7"
        await s.refreshVaultNotes()
        XCTAssertEqual(s.vaultNotes.map(\.name), ["Pasta.md", "Roadmap.md", "Hone.md"])   // open, linked, matched

        s.removeVaultNote(s.vaultNotes[0])
        await s.refreshVaultNotes()
        XCTAssertEqual(s.vaultNotes.map(\.name), ["Roadmap.md", "Hone.md"])               // removed stays out

        replies = [.text(["<improved_prompt>\nX\n</improved_prompt>"])]
        s.run()
        await settle(s)
        let sent = calls.first?.first?.content ?? ""
        XCTAssertTrue(sent.contains("<obsidian_note name=\"Hone.md\">\nHone: SwiftUI app, XCTest tests, quick panel.\n</obsidian_note>"))
        XCTAssertTrue(sent.contains("Ship Obsidian context."))
        XCTAssertFalse(sent.contains("Boil water"))
        XCTAssertEqual(s.conversation.first?.content, sent)    // the live run keeps the text for follow-ups
        let saved = s.history.first?.conversation.first?.content ?? ""
        XCTAssertTrue(saved.contains("<obsidian_note name=\"Roadmap.md\">\n(note text not kept in history)\n</obsidian_note>"))
        XCTAssertFalse(saved.contains("Ship Obsidian context."))

        s.reset()
        XCTAssertEqual(s.vaultNotes, [])
        s.sourceApp = "Obsidian — Pasta - Work - Obsidian v1.7.7"
        await s.refreshVaultNotes()
        XCTAssertEqual(s.vaultNotes.first?.name, "Pasta.md")  // reset forgets removals
    }

    func testPanelGetsOnlyItsOwnVaultNotes() async throws {
        let root = try vault(["Hone.md": "Hone"])
        let s = makeState()
        s.obsidianVault = root.path
        s.notes = "[[Hone]]"                                  // main-window notes don't reach panel runs
        let none = await s.relevantNotes(text: "proofread this", notes: "", source: "")
        XCTAssertEqual(none, [])
        let linked = await s.relevantNotes(text: "see [[Hone]]", notes: "", source: "")
        XCTAssertEqual(linked.map(\.name), ["Hone.md"])
        XCTAssertEqual(s.panelOptions(source: "Mail", vaultNotes: linked).context.vaultNotes.map(\.name), ["Hone.md"])
        XCTAssertTrue(s.panelOptions(source: "Mail").context.vaultNotes.isEmpty)
    }

    func testCorrectionsReplaceAnswersWhenThereAreAssumptions() async {
        let reply = "<improved_prompt>\nAdd XCTest tests.\n</improved_prompt>\n<assumptions>\n- Tests use XCTest\n- Target is macOS 14\n</assumptions>"
        replies = [.text([reply]), .text([reply])]
        let s = makeState()
        s.submitAnswers()                                 // no result yet: nothing sent
        s.draft = "write tests"
        s.run()
        await settle(s)
        XCTAssertEqual(s.result?.followUps, ["Tests use XCTest", "Target is macOS 14"])
        s.answers = ["Tests use XCTest": "Swift Testing", "Target is macOS 14": " "]
        s.submitAnswers()
        await settle(s)
        let sent = calls.last?.last?.content ?? ""
        XCTAssertTrue(sent.contains("<corrections>\nAssumed: Tests use XCTest\nActually: Swift Testing\n</corrections>"))
        XCTAssertFalse(sent.contains("macOS 14"))
    }
}

/// A provider that replays a scripted reply and records the messages it was sent.
private struct FakeProvider: LLMProvider {
    let reply: AppStateTests.Reply
    let record: ([ChatMessage]) -> Void

    func stream(system: String, messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        record(messages)
        return AsyncThrowingStream { c in
            switch reply {
            case .text(let chunks):
                for chunk in chunks { c.yield(chunk) }
                c.finish()
            case .failure(let error):
                c.finish(throwing: error)
            case .hang, .noProvider:
                break
            }
        }
    }
}
