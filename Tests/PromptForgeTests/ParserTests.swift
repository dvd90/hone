import XCTest
@testable import PromptForge

final class ParserTests: XCTestCase {
    func testFullReply() {
        let raw = """
        <score_before>42</score_before>
        <diagnosis>
        - Vague task
        * No output format
        </diagnosis>
        <improved_prompt>
        <instructions>Summarize {{DOC}}.</instructions>
        </improved_prompt>
        <changes>
        1. Added XML tags
        2) Added a variable
        </changes>
        <questions>
        None
        </questions>
        <score_after>88/100</score_after>
        """
        let r = ForgeResult.parse(raw)
        XCTAssertEqual(r.scoreBefore, 42)
        XCTAssertEqual(r.scoreAfter, 88)
        XCTAssertEqual(r.diagnosis, ["Vague task", "No output format"])
        XCTAssertEqual(r.improvedPrompt, "<instructions>Summarize {{DOC}}.</instructions>")
        XCTAssertEqual(r.changes, ["Added XML tags", "Added a variable"])
        XCTAssertEqual(r.questions, [])
    }

    func testPartialStream() {
        let r = ForgeResult.parse("<score_before>30</score_before>\n<diagnosis>\n- x\n</diagnosis>\n<improved_prompt>\nHello wor</impr")
        XCTAssertEqual(r.scoreBefore, 30)
        XCTAssertEqual(r.improvedPrompt, "Hello wor")
        XCTAssertNil(r.scoreAfter)
    }

    func testPromptUserMessage() {
        let m = MetaPrompt.userMessage(draft: "write a poem", context: PromptContext(), target: .gpt, depth: .light, techniques: [.examples])
        XCTAssertTrue(m.contains("<draft_prompt>\nwrite a poem\n</draft_prompt>"))
        XCTAssertTrue(m.contains("Examples:"))
        XCTAssertFalse(m.contains("<context>"))
    }

    func testTransformAction() {
        let proof = AIAction.builtIns.first { $0.id == "proofread" }!
        let msg = ActionEngine.firstMessage(action: proof, text: "teh cat", options: PromptOptions())
        XCTAssertTrue(msg.content.contains("<text>\nteh cat\n</text>"))
        XCTAssertEqual(ActionEngine.system(for: proof), ActionEngine.transformSystem)
        XCTAssertEqual(ActionEngine.displayText(action: proof, raw: "  the cat\n"), "the cat")
    }

    func testFlowLayoutWraps() {
        let chip = CGSize(width: 40, height: 10)
        let r = FlowLayout.arrange([chip, chip, chip], width: 100, spacing: 5)
        XCTAssertEqual(r.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 45, y: 0), CGPoint(x: 0, y: 15)])
        XCTAssertEqual(r.size, CGSize(width: 85, height: 25))
    }

    func testBuiltInIDsUnique() {
        XCTAssertEqual(Set(AIAction.builtIns.map(\.id)).count, AIAction.builtIns.count)
    }

    func testFlattenConversation() {
        XCTAssertEqual(CLIProvider.flatten([ChatMessage(role: "user", content: "hi")]), "hi")
        let f = CLIProvider.flatten([
            ChatMessage(role: "user", content: "a"),
            ChatMessage(role: "assistant", content: "b"),
            ChatMessage(role: "user", content: "c"),
        ])
        XCTAssertTrue(f.contains("<assistant>\nb\n</assistant>"))
        XCTAssertTrue(f.hasSuffix("c"))
    }
}
