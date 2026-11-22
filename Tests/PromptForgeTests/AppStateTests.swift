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
        s.goal = "for devs"
        XCTAssertEqual(s.promptOptions.goal, "for devs")
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
        XCTAssertEqual(s.history.first?.goal, "")   // goal is only kept for Improve Prompt
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
        s.goal = "devs"
        s.selectedActionID = AIAction.improvePrompt.id
        s.run()
        await settle(s)
        let item = s.history[0]

        s.reset()
        XCTAssertEqual(s.draft, ""); XCTAssertEqual(s.goal, ""); XCTAssertEqual(s.raw, "")
        s.selectedActionID = "summarize"         // a different action is selected when reopening
        s.open(item)
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)
        XCTAssertEqual(s.output, "Write tests for Hone.")
        XCTAssertEqual(s.goal, "devs")
        XCTAssertEqual(s.currentID, item.id)

        var orphan = item
        orphan.actionID = "deleted-custom-action"
        s.open(orphan)
        XCTAssertEqual(s.selectedActionID, AIAction.improvePrompt.id)

        s.clearOutput()
        s.load(action: .improvePrompt, draft: "write tests", raw: item.raw)
        XCTAssertEqual(s.result?.improvedPrompt, "Write tests for Hone.")
        XCTAssertEqual(s.currentID, item.id)
        let proofread = AIAction.builtIns.first { $0.id == "proofread" }!
        s.load(action: proofread, draft: "teh", raw: "the")
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
