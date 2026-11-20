import XCTest
@testable import PromptForge

/// Saved data must survive app updates: missing fields and unknown enum values fall back instead of wiping everything.
final class PersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ json: String) throws -> URL {
        let file = dir.appendingPathComponent("history-v2.json")
        try Data(json.utf8).write(to: file)
        return file
    }

    func testProviderSettingsKeepKnownFields() throws {
        let s = try JSONDecoder().decode(ProviderSettings.self, from: Data(#"{"kind":"someFutureProvider","codexModel":"o5"}"#.utf8))
        XCTAssertEqual(s.kind, .claudeCode)
        XCTAssertEqual(s.codexModel, "o5")
        XCTAssertEqual(s.openAIBaseURL, ProviderSettings().openAIBaseURL)

        var full = ProviderSettings()
        full.kind = .openAICompatible
        full.claudeCodeModel = "opus"; full.codexModel = "o5"; full.geminiModel = "pro"
        full.anthropicModel = "claude-opus-5-5"; full.openAIBaseURL = "http://localhost:1234/v1"; full.openAIModel = "llama"
        XCTAssertEqual(try JSONDecoder().decode(ProviderSettings.self, from: JSONEncoder().encode(full)), full)
        // Tripwire: a new stored property needs a line in init(from:) and a non-default value above.
        XCTAssertEqual(Mirror(reflecting: full).children.count, 7)
    }

    func testCustomActionsKeepKnownFields() throws {
        let a = try JSONDecoder().decode([AIAction].self, from: Data(#"[{"id":"custom-1","name":"Tweet","instruction":"Make it a tweet","kind":"futureKind"}]"#.utf8))
        XCTAssertEqual(a.first?.instruction, "Make it a tweet")
        XCTAssertEqual(a.first?.kind, .transform)
        XCTAssertEqual(a.first?.icon, "sparkles")

        let full = AIAction(id: "x", name: "N", icon: "star", instruction: "I", kind: .promptEngineer, builtIn: true)
        XCTAssertEqual(try JSONDecoder().decode(AIAction.self, from: JSONEncoder().encode(full)), full)
        // Tripwire: a new stored property needs a line in init(from:) and a non-default value above.
        XCTAssertEqual(Mirror(reflecting: full).children.count, 6)
    }

    func testHistoryRoundTripAndOldFiles() throws {
        let item = HistoryItem(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000), actionID: "proofread",
                               actionName: "Proofread", draft: "teh", goal: "g", target: .gpt, provider: "Codex",
                               raw: "the", conversation: [ChatMessage(role: "user", content: "teh")])
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let file = dir.appendingPathComponent("history-v2.json")
        try enc.encode([item]).write(to: file)
        XCTAssertEqual(HistoryStore.load(from: file), [item])

        // Missing fields and a renamed target keep the item instead of dropping the whole history.
        let old = try write(#"[{"id":"\#(item.id)","date":"2027-01-15T08:00:00Z","actionID":"proofread","draft":"teh","raw":"the","target":"Retired Target"}]"#)
        let loaded = HistoryStore.load(from: old)
        XCTAssertEqual(loaded.first?.raw, "the")
        XCTAssertEqual(loaded.first?.target, .claude)
        XCTAssertEqual(loaded.first?.conversation, [])
    }

    func testUnreadableHistoryIsMovedAsideNotOverwritten() throws {
        let file = try write("not json")
        XCTAssertEqual(HistoryStore.load(from: file), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept[0].hasPrefix("history-v2.unreadable-"))
    }
}
