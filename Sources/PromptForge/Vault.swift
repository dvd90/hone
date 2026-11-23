import Foundation

/// Obsidian notes as Improve Prompt context. Obsidian keeps notes as Markdown files and Hone isn't sandboxed,
/// so this is plain file reading: no plugin, no API, no network.
enum Obsidian {
    /// Where Obsidian lists its vaults.
    static let registry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")

    /// Vault folders Obsidian knows about, most recently opened first; missing folders are skipped.
    static func vaults(registry: URL = registry) -> [URL] {
        struct Vault: Decodable { var path: String; var ts: Double? }
        struct Registry: Decodable { var vaults: [String: Vault] }
        guard let data = try? Data(contentsOf: registry),
              let list = try? JSONDecoder().decode(Registry.self, from: data) else { return [] }
        return list.vaults.values
            .sorted { ($0.ts ?? 0, $1.path) > ($1.ts ?? 0, $0.path) }
            .map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Targets of `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]` and `![[Note]]`, in order, without duplicates.
    static func links(in text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\[\[([^\[\]|#^\n]+)"#)
        var seen = Set<String>()
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            let target = (text as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            return !target.isEmpty && seen.insert(target.lowercased()).inserted ? target : nil
        }
    }

    /// The note open in Obsidian, from a source description like "Obsidian — Note - Vault - Obsidian v1.7.7".
    static func openNote(source: String, vault: String) -> String? {
        let prefix = "Obsidian — "
        guard source.hasPrefix(prefix) else { return nil }
        let start = source.index(source.startIndex, offsetBy: prefix.count)
        guard let end = source.range(of: " - \(vault) - Obsidian v", options: .backwards, range: start..<source.endIndex),
              end.lowerBound > start else { return nil }
        return String(source[start..<end.lowerBound])
    }

    /// Lowercased words without accents. `minLength` drops short words ("a", "de", "11") from scoring.
    static func words(_ s: String, minLength: Int = 3) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count >= minLength }
            .map(String.init)
    }

    /// Obsidian's Settings → Files and links → Excluded files: a folder or file prefix, or `/regex/`.
    static func isExcluded(_ path: String, filters: [String]) -> Bool {
        filters.contains { f in
            if f.count > 2, f.hasPrefix("/"), f.hasSuffix("/") {
                return path.range(of: String(f.dropFirst().dropLast()), options: .regularExpression) != nil
            }
            return !f.isEmpty && path.hasPrefix(f)
        }
    }

    /// History keeps which notes a run used, not their text. Only the context block of an Improve Prompt message
    /// is touched (MetaPrompt puts it right after </techniques>, before the draft), and fencing guarantees a note
    /// body never contains its own closing tag or </context>.
    static func redacted(_ message: ChatMessage) -> ChatMessage {
        guard message.role == "user", let start = message.content.range(of: "</techniques>\n\n<context>\n"),
              let end = message.content.range(of: "\n</context>", range: start.upperBound..<message.content.endIndex)
        else { return message }
        let context = message.content[start.upperBound..<end.lowerBound].replacingOccurrences(
            of: #"(<obsidian_note name="[^"\n]*">\n)[\s\S]*?(\n</obsidian_note>)"#,
            with: "$1(note text not kept in history)$2", options: .regularExpression)
        return ChatMessage(role: message.role,
                           content: String(message.content[..<start.upperBound]) + context + message.content[end.lowerBound...])
    }

    /// The vaults to offer in Settings: Obsidian's, plus `current` when it was chosen by hand.
    static func choices(current: String, registry: URL = registry) -> [String] {
        let known = vaults(registry: registry).map(\.path)
        return current.isEmpty || known.contains(current) ? known : known + [current]
    }
}

/// Word counts for every note in one vault. Each refresh re-reads only notes whose modification date changed.
/// An actor so indexing and ranking stay off the main thread while the user types.
actor VaultIndex {
    struct Note {
        var title: String
        var modified: Date
        var counts: [String: Int]
        var length: Int
    }

    /// Up to 5 notes and about 30 KB per run; at most 3 of them picked by ranking rather than linked or open.
    static let maxNotes = 5, maxRanked = 3, maxBytes = 30_000
    /// Notes larger than this are skipped: they are logs or exports, not context.
    static let maxNoteBytes = 1_000_000

    let root: URL
    private(set) var notes: [String: Note] = [:]   // by path relative to the vault

    init(root: URL) { self.root = root }

    func refresh() {
        let filters = excludedFiles()
        var fresh: [String: Note] = [:]
        // ponytail: walks the vault each refresh (stat only, unchanged notes reuse their counts); fine for
        // thousands of notes. Switch to FSEvents if very large vaults make chips lag.
        let walker = FileManager.default.enumerator(atPath: root.path)
        while let path = walker?.nextObject() as? String {
            if (path as NSString).lastPathComponent.hasPrefix(".") { walker?.skipDescendants(); continue }
            guard path.lowercased().hasSuffix(".md"), !Obsidian.isExcluded(path, filters: filters),
                  let attrs = walker?.fileAttributes, attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.size] as? Int ?? 0) <= Self.maxNoteBytes else { continue }
            let modified = attrs[.modificationDate] as? Date ?? .distantPast
            if let known = notes[path], known.modified == modified { fresh[path] = known; continue }
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else { continue }
            let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let words = Obsidian.words(title + "\n" + text)
            fresh[path] = Note(title: title, modified: modified, counts: words.reduce(into: [:]) { $0[$1, default: 0] += 1 },
                               length: words.count)
        }
        notes = fresh
    }

    /// The vault's own exclusion list, from `.obsidian/app.json`.
    private func excludedFiles() -> [String] {
        struct App: Decodable { var userIgnoreFilters: [String]? }
        let url = root.appendingPathComponent(".obsidian/app.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(App.self, from: $0) }?.userIgnoreFilters ?? []
    }

    /// Resolves a link or title the way Obsidian does: exact path first, else the shortest path with that name.
    func resolve(_ name: String) -> String? {
        var key = name.lowercased()
        if key.hasSuffix(".md") { key.removeLast(3) }
        return notes.keys
            .filter { let p = $0.lowercased(); return p == key + ".md" || p.hasSuffix("/" + key + ".md") }
            .min { ($0.count, $0) < ($1.count, $1) }
    }

    /// Notes worth sending, best first. A note scores the share of the query's distinctive words it covers
    /// (BM25 divided by the query's total word weight, so long generic drafts don't match everything), plus a
    /// bonus when its title appears in the query, worth 1 per title word found in no other note.
    func ranked(for query: String, minScore: Double) -> [String] {
        let terms = Set(Obsidian.words(query))
        guard !terms.isEmpty, !notes.isEmpty else { return [] }
        let n = Double(notes.count)
        let avgLength = max(1, Double(notes.values.reduce(0) { $0 + $1.length }) / n)
        let rarest = log(1 + (n - 0.5) / 1.5)   // idf of a word found in one note
        var idf: [String: Double] = [:]
        for t in terms {
            let df = Double(notes.values.filter { $0.counts[t] != nil }.count)
            idf[t] = log(1 + (n - df + 0.5) / (df + 0.5)) / rarest
        }
        let mass = idf.values.reduce(0, +)
        // Titles match as whole phrases, short words included, so "2026-11-23" doesn't match every "2026".
        let phrase = " " + Obsidian.words(query, minLength: 1).joined(separator: " ") + " "
        return notes.compactMap { path, note -> (String, Double)? in
            var score = terms.reduce(0.0) { sum, t in
                guard let c = note.counts[t] else { return sum }
                let tf = Double(c)
                return sum + idf[t, default: 0] * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * Double(note.length) / avgLength))
            } / mass
            if phrase.contains(" " + Obsidian.words(note.title, minLength: 1).joined(separator: " ") + " ") {
                score += Obsidian.words(note.title).reduce(0) { $0 + idf[$1, default: 0] }
            }
            return score >= minScore ? (path, score) : nil
        }
        .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
        .map(\.0)
    }

    /// The notes for one run, in priority order: the note open in Obsidian, `[[linked]]` notes, then the best
    /// matches for the query. Refreshes first so edits made in Obsidian count.
    func pick(open: String?, links: [String], query: String, minScore: Double, excluding: Set<String> = []) -> [Attachment] {
        refresh()
        let explicit = ([open].compactMap { $0 } + links).compactMap(resolve)
        let ranked = self.ranked(for: query, minScore: minScore).prefix(Self.maxRanked)
        var seen = excluding, out: [Attachment] = [], left = Self.maxBytes
        for path in explicit + ranked where out.count < Self.maxNotes && left > 0 && seen.insert(path).inserted {
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else { continue }
            let body = text.utf8.count <= left ? text : String(decoding: text.utf8.prefix(left), as: UTF8.self) + "\n[…]"
            left -= body.utf8.count
            out.append(Attachment(name: path, text: body))
        }
        return out
    }
}
