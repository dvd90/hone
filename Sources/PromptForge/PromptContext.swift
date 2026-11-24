import Foundation

/// Reusable notes about the author or a project, sent as context with Improve Prompt. Persisted in UserDefaults.
struct ContextProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "New profile"
    var text = ""
}

extension ContextProfile {
    // Persisted: a new stored property needs a line here and an updated tripwire in PersistenceTests.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decode(.id, or: UUID())
        name = c.decode(.name, or: "Untitled profile")
        text = c.decode(.text, or: "")
    }
}

/// A text file attached to one Improve Prompt run. Its contents go to the chosen provider with the draft.
struct Attachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String

    /// About 12k tokens per file and 25k in total: enough for a spec or a CLAUDE.md, small enough that
    /// every follow-up (which resends the context) and the history file stay reasonable.
    static let maxBytes = 50_000
    static let maxTotalBytes = 100_000

    enum ReadError: LocalizedError, Equatable {
        case tooLarge(String)
        case notText(String)
        case unreadable(String)
        case overTotal(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let name): return "“\(name)” is too large to attach. The limit is 50 KB per file."
            case .notText(let name): return "“\(name)” isn't a text file, so it can't be attached."
            case .unreadable(let name): return "Couldn't read “\(name)”."
            case .overTotal(let name): return "“\(name)” would take attachments past the 100 KB total. Remove a file first."
            }
        }
    }

    /// Reads a UTF-8 text file, checking the size before loading it.
    static func read(_ url: URL) throws -> Attachment {
        let name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { throw ReadError.notText(name) }
        if let size = values?.fileSize, size > maxBytes { throw ReadError.tooLarge(name) }
        guard let data = try? Data(contentsOf: url) else { throw ReadError.unreadable(name) }
        guard data.count <= maxBytes else { throw ReadError.tooLarge(name) }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw ReadError.notText(name) }
        return Attachment(name: name, text: text)
    }
}

/// Everything Improve Prompt knows about the author's situation for one run.
struct PromptContext: Equatable {
    var profile: ContextProfile?
    var notes = ""
    /// The app and window the author came from (hotkey only), e.g. "Xcode — AppState.swift".
    var source = ""
    var files: [Attachment] = []
    /// Notes from the Obsidian vault picked for this run (Vault.swift); names are paths inside the vault.
    var vaultNotes: [Attachment] = []
}

enum SourceContext {
    /// "App — Window title"; the title adds the document or project when the app shows one.
    static func describe(appName: String?, windowTitle: String?) -> String {
        let app = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if app.isEmpty { text = title }
        else if title.isEmpty || title == app { text = app }
        else { text = "\(app) — \(title)" }
        return String(text.prefix(300))
    }
}
