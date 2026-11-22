import XCTest
@testable import PromptForge

/// Targets, depths, techniques, history items and action wording.
final class ModelTests: XCTestCase {
    func testEveryTargetDepthAndTechniqueHasGuidance() {
        for t in TargetModel.allCases {
            XCTAssertEqual(t.id, t.rawValue)
            XCTAssertTrue(t.guidance.hasPrefix("Target"), t.rawValue)
        }
        for d in Depth.allCases {
            XCTAssertEqual(d.id, d.rawValue)
            XCTAssertFalse(d.guidance.isEmpty)
        }
        XCTAssertTrue(Depth.thorough.guidance.contains("{{VARIABLES}}"))
        for t in Technique.allCases {
            XCTAssertEqual(t.id, t.rawValue)
            XCTAssertFalse(t.icon.isEmpty)
            XCTAssertTrue(t.instruction.hasSuffix("."), t.rawValue)
        }
        XCTAssertEqual(Set(Technique.allCases.map(\.icon)).count, Technique.allCases.count)
        XCTAssertTrue(ModelPreset.all.contains { $0.id == ModelPreset.defaultID })
    }

    func testParserEdgeCases() {
        // A "<" late in a stream that is already a complete tag is kept, not stripped as a half tag.
        XCTAssertEqual(ForgeResult.parse("<improved_prompt>\nUse <b>bold</b>").improvedPrompt, "Use <b>bold</b>")
        XCTAssertEqual(ForgeResult.parse("<score_before>250</score_before>").scoreBefore, 100)
        XCTAssertNil(ForgeResult.parse("<score_before>n/a</score_before>").scoreBefore)
        XCTAssertEqual(ForgeResult.parse("no tags at all"), ForgeResult.empty)
    }

    func testHistoryItemDerivedValues() {
        var item = HistoryItem(id: UUID(), date: Date(), actionID: AIAction.improvePrompt.id, actionName: "Improve Prompt",
                               draft: String(repeating: "a", count: 80) + "\nsecond line", goal: "", target: .claude,
                               provider: "Claude Code", raw: "<improved_prompt>\nBetter\n</improved_prompt>", conversation: [])
        XCTAssertTrue(item.isPrompt)
        XCTAssertEqual(item.output, "Better")
        XCTAssertEqual(item.title, String(repeating: "a", count: 70) + "…")

        item.actionID = "proofread"
        item.raw = "  fixed  "
        item.draft = ""
        XCTAssertFalse(item.isPrompt)
        XCTAssertNil(item.result)
        XCTAssertEqual(item.output, "fixed")
        XCTAssertEqual(item.title, "Untitled")
        item.draft = "short draft"
        XCTAssertEqual(item.title, "short draft")
    }

    func testHistoryStoreLocation() {
        XCTAssertEqual(HistoryStore.url.lastPathComponent, "history-v2.json")
        XCTAssertEqual(HistoryStore.url.deletingLastPathComponent().lastPathComponent, "PromptForge")
        XCTAssertTrue(HistoryStore.load(from: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).json")).isEmpty)
    }

    func testFollowUpWording() {
        let proofread = AIAction.builtIns.first { $0.id == "proofread" }!
        XCTAssertTrue(ActionEngine.followUp(action: proofread, feedback: "shorter").hasPrefix("Revise your previous output"))
        XCTAssertTrue(ActionEngine.followUp(action: .improvePrompt, feedback: "shorter").hasPrefix("Revise the improved prompt"))
        XCTAssertEqual(ActionEngine.system(for: .improvePrompt), MetaPrompt.system)
        XCTAssertEqual(ActionEngine.displayText(action: .improvePrompt, raw: "<improved_prompt>\nX\n</improved_prompt>"), "X")
        let custom = AIAction.newCustom()
        XCTAssertTrue(custom.id.hasPrefix("custom-"))
        XCTAssertFalse(custom.builtIn)
    }

    @MainActor
    func testHotKeyChoiceIsSaved() throws {
        let suite = "PF-hotkey-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults, historyURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("PF-\(UUID().uuidString).json")) { _ in throw ForgeError.config("unused") }
        state.hotKey = .off                       // .off registers no global hotkey from the test process
        XCTAssertEqual(defaults.string(forKey: "hotKey"), "off")
    }
}
