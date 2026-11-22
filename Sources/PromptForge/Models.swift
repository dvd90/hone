import Foundation

enum TargetModel: String, CaseIterable, Identifiable, Codable {
    case claude = "Claude"
    case gpt = "GPT"
    case gemini = "Gemini"
    case generic = "Any LLM"
    case codingAgent = "Coding agent"
    case image = "Image model"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .claude:
            return "Target is a Claude model. Use XML tags to separate instructions, context, data and examples. Claude follows instructions precisely and literally: state the desired behavior and level of effort explicitly, and explain why constraints exist."
        case .gpt:
            return "Target is an OpenAI GPT model. Use Markdown headings (Role, Instructions, Context, Output format) and clear delimiters for data. Put the most important instructions first; for long prompts restate critical ones at the end."
        case .gemini:
            return "Target is a Google Gemini model. Use clear headings or XML-style tags, state the task first, give an explicit output format, and place long context before the final question."
        case .generic:
            return "Target model is unknown. Use portable structure: Markdown headings plus clear delimiters for data. Avoid model-specific features."
        case .codingAgent:
            return "Target is an agentic coding assistant (e.g. Claude Code, Cursor). Specify the goal, relevant files/paths, constraints (style, dependencies, tests), definition of done, how to verify (commands to run), and what NOT to touch. Ask it to plan before editing and to report what it actually tested."
        case .image:
            return "Target is a text-to-image model. Produce one dense descriptive prompt: subject, composition, setting, lighting, style/medium, camera/lens if photographic, palette, mood, aspect ratio. Comma-separated descriptive phrases; no instructions, no XML. Add a separate 'Negative prompt:' line only if useful."
        }
    }
}

enum Depth: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case standard = "Standard"
    case thorough = "Production"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .light:
            return "Light touch: make minimal, high-leverage edits. Keep the author's wording and roughly the same length; fix ambiguity, missing context and missing output format only."
        case .standard:
            return "Standard: restructure as needed for clarity and effectiveness, but keep it as short as the task allows."
        case .thorough:
            return "Production-grade: a reusable prompt suitable as a system prompt — role, context, detailed instructions, edge cases, output format, and examples where useful. Use {{VARIABLES}} for inputs that change between uses."
        }
    }
}

enum Technique: String, CaseIterable, Identifiable, Codable {
    case role = "Role"
    case context = "Context & why"
    case successCriteria = "Success criteria"
    case structure = "Structure / tags"
    case examples = "Examples"
    case reasoning = "Step-by-step"
    case outputFormat = "Output format"
    case edgeCases = "Edge cases"
    case variables = "Variables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .role: return "person.crop.square"
        case .context: return "text.book.closed"
        case .successCriteria: return "checkmark.seal"
        case .structure: return "chevron.left.forwardslash.chevron.right"
        case .examples: return "list.bullet.rectangle"
        case .reasoning: return "brain"
        case .outputFormat: return "doc.richtext"
        case .edgeCases: return "exclamationmark.triangle"
        case .variables: return "curlybraces"
        }
    }

    var instruction: String {
        switch self {
        case .role: return "Give the model a specific expert role suited to the task."
        case .context: return "Add the context and the motivation behind instructions so the model can generalize."
        case .successCriteria: return "State explicitly what a great result looks like and how it will be judged."
        case .structure: return "Separate instructions, context, data and examples with clear sections or tags."
        case .examples: return "Add 1-3 diverse, clearly delimited examples of input and ideal output."
        case .reasoning: return "Ask the model to think through the problem step by step (or plan) before the final answer."
        case .outputFormat: return "Specify the exact output format, structure and length."
        case .edgeCases: return "Cover realistic edge cases and what to do when information is missing or ambiguous."
        case .variables: return "Turn changing inputs into {{VARIABLE}} placeholders so the prompt is a reusable template."
        }
    }
}

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct ModelPreset: Identifiable {
    let id: String
    let label: String

    static let defaultID = "claude-sonnet-5-5"
    static let all: [ModelPreset] = [
        ModelPreset(id: "claude-sonnet-5-5", label: "Claude Sonnet 5.5 — balanced"),
        ModelPreset(id: "claude-opus-5-5", label: "Claude Opus 5.5 — best quality"),
        ModelPreset(id: "claude-haiku-5-5", label: "Claude Haiku 5.5 — fastest"),
    ]
}

struct ForgeResult: Codable, Equatable {
    var scoreBefore: Int?
    var scoreAfter: Int?
    var diagnosis: [String] = []
    var improvedPrompt: String = ""
    var changes: [String] = []
    var questions: [String] = []

    static let empty = ForgeResult()

    /// Tolerant parser: works on complete replies and on partial streamed text.
    static func parse(_ raw: String) -> ForgeResult {
        var r = ForgeResult()
        var head = Substring(raw)
        var tail = Substring("")

        if let open = raw.range(of: "<improved_prompt>") {
            head = raw[..<open.lowerBound]
            let after = raw[open.upperBound...]
            if let close = after.range(of: "</improved_prompt>", options: .backwards) {
                r.improvedPrompt = trim(after[..<close.lowerBound])
                tail = after[close.upperBound...]
            } else {
                r.improvedPrompt = trim(stripPartialTag(after))
            }
        }

        r.scoreBefore = score(extract("score_before", in: head))
        r.diagnosis = bullets(extract("diagnosis", in: head))
        r.changes = bullets(extract("changes", in: tail))
        r.questions = bullets(extract("questions", in: tail))
        r.scoreAfter = score(extract("score_after", in: tail))
        return r
    }

    static func extract(_ tag: String, in s: Substring) -> String? {
        guard let open = s.range(of: "<\(tag)>") else { return nil }
        let rest = s[open.upperBound...]
        let body = rest.range(of: "</\(tag)>").map { rest[..<$0.lowerBound] } ?? stripPartialTag(rest)
        return trim(body)
    }

    static func bullets(_ s: String?) -> [String] {
        guard let s else { return [] }
        return s.split(whereSeparator: \.isNewline).map { line -> String in
            var t = line.trimmingCharacters(in: .whitespaces)
            while let f = t.first, "-*•".contains(f) { t.removeFirst() }
            if let r = t.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) { t.removeSubrange(r) }
            return t.trimmingCharacters(in: .whitespaces)
        }.filter {
            let l = $0.lowercased()
            return !$0.isEmpty && l != "none" && l != "none."
        }
    }

    private static func score(_ s: String?) -> Int? {
        guard let s, let r = s.range(of: #"\d{1,3}"#, options: .regularExpression), let n = Int(s[r]) else { return nil }
        return min(max(n, 0), 100)
    }

    private static func trim<S: StringProtocol>(_ s: S) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops a half-streamed tag like "</impro" at the end of a chunk.
    private static func stripPartialTag(_ s: Substring) -> Substring {
        guard let lt = s.range(of: "<", options: .backwards) else { return s }
        let fragment = s[lt.lowerBound...]
        if !fragment.contains(">") && fragment.count < 24 { return s[..<lt.lowerBound] }
        return s
    }
}

struct HistoryItem: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var actionID: String
    var actionName: String
    var draft: String
    var goal: String
    var target: TargetModel
    var provider: String
    var raw: String
    var conversation: [ChatMessage]

    var isPrompt: Bool { actionID == AIAction.improvePrompt.id }
    var result: ForgeResult? { isPrompt ? ForgeResult.parse(raw) : nil }
    var output: String { isPrompt ? (result?.improvedPrompt ?? "") : raw.trimmingCharacters(in: .whitespacesAndNewlines) }

    var title: String {
        let first = draft.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled"
        return first.count > 70 ? String(first.prefix(70)) + "…" : first
    }
}

extension HistoryItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decode(.id, or: UUID())
        date = c.decode(.date, or: Date())
        actionID = c.decode(.actionID, or: "")
        actionName = c.decode(.actionName, or: "")
        draft = c.decode(.draft, or: "")
        goal = c.decode(.goal, or: "")
        target = c.decode(.target, or: .claude)
        provider = c.decode(.provider, or: "")
        raw = c.decode(.raw, or: "")
        conversation = c.decode(.conversation, or: [])
    }
}

extension KeyedDecodingContainer {
    /// A missing or unreadable value falls back instead of failing the whole decode, so adding a field
    /// or renaming an enum case never wipes saved data. Every persisted type's `init(from:)` uses this.
    func decode<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

enum HistoryStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history-v2.json")
    }

    static func load(from file: URL = HistoryStore.url) -> [HistoryItem] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode([HistoryItem].self, from: data)
        } catch {
            // Move an unreadable file aside so the next save can't overwrite the user's history.
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            return []
        }
    }

    static func save(_ items: [HistoryItem], to file: URL = HistoryStore.url) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(items) { try? data.write(to: file, options: .atomic) }
    }
}
