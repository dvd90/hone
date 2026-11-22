import Foundation

/// Uses an installed, logged-in CLI so requests run on the user's existing subscription
/// (Claude Pro/Max via Claude Code, ChatGPT via Codex, Google via Gemini CLI). No API key needed.
struct CLIProvider: LLMProvider {
    enum Tool: String {
        case claude, codex, gemini

        var displayName: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .gemini: return "Gemini CLI"
            }
        }
    }

    let tool: Tool
    let model: String
    /// Process environment (PATH lookup). Nil reads the login shell's; tests inject a PATH with fake CLIs.
    var environment: [String: String]? = nil

    /// One parsed line of Claude Code's stream-json output.
    enum ClaudeLine: Equatable {
        case text(String)
        case result(String, isError: Bool)
        case other
        case notJSON
    }

    func stream(system: String, messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        let tool = self.tool
        let model = self.model.trimmingCharacters(in: .whitespaces)
        let environment = self.environment

        return AsyncThrowingStream { continuation in
            let process = Process()
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let env: [String: String]
                    if let environment { env = environment } else { env = await ShellEnvironment.shared.load() }
                    guard let exe = ShellEnvironment.find(tool.rawValue, in: env) else {
                        throw ForgeError.config("Couldn't find the `\(tool.rawValue)` command. Install \(tool.displayName) or pick another provider in Settings.")
                    }

                    // Run in an empty scratch folder so no project config (CLAUDE.md, AGENTS.md…) leaks in.
                    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("PromptForge-cli", isDirectory: true)
                    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

                    let outFile = tool == .codex ? workDir.appendingPathComponent("codex-\(UUID().uuidString).txt") : nil
                    let args = Self.arguments(tool: tool, model: model, system: system, outFile: outFile)
                    let input = Self.input(tool: tool, system: system, messages: messages)

                    process.executableURL = exe
                    process.arguments = args
                    process.environment = env
                    process.currentDirectoryURL = workDir
                    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr
                    // The exit status arrives through terminationHandler, set before run() so it can't be missed.
                    // (waitUntilExit needs a run loop, which the cooperative thread pool doesn't service, and can hang.)
                    let exited = AsyncStream<Int32> { c in
                        process.terminationHandler = { c.yield($0.terminationStatus); c.finish() }
                    }
                    try process.run()

                    // Blocking pipe I/O runs on GCD threads, never on the cooperative pool.
                    let inputData = Data(input.utf8), stdinHandle = stdin.fileHandleForWriting
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? stdinHandle.write(contentsOf: inputData)
                        try? stdinHandle.close()
                    }
                    let errTask = Task { await Self.readToEnd(stderr.fileHandleForReading) }

                    var stdoutTail = ""
                    switch tool {
                    case .claude:
                        var gotText = false
                        for try await line in stdout.fileHandleForReading.bytes.lines {
                            switch Self.parseClaudeLine(line) {
                            case .text(let text):
                                gotText = true
                                continuation.yield(text)
                            case let .result(resultText, isError):
                                if isError {
                                    throw ForgeError.cli(tool.displayName, resultText.isEmpty ? "unknown error" : resultText)
                                }
                                if !gotText && !resultText.isEmpty { continuation.yield(resultText) }
                            case .notJSON:
                                stdoutTail = String((stdoutTail + line + "\n").suffix(600))
                            case .other:
                                break
                            }
                        }
                    case .gemini:
                        for try await line in stdout.fileHandleForReading.bytes.lines {
                            continuation.yield(line + "\n")
                            stdoutTail = String((stdoutTail + line + "\n").suffix(600))
                        }
                    case .codex:
                        let data = await Self.readToEnd(stdout.fileHandleForReading)
                        stdoutTail = String((String(data: data, encoding: .utf8) ?? "").suffix(600))
                    }

                    var status: Int32 = -1
                    for await code in exited { status = code }
                    let errText = String(data: await errTask.value, encoding: .utf8) ?? ""

                    if let f = outFile {
                        if let text = try? String(contentsOf: f, encoding: .utf8), !text.isEmpty {
                            continuation.yield(text)
                        }
                        try? FileManager.default.removeItem(at: f)
                    }

                    if status != 0 {
                        let detail = [errText, stdoutTail].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "exit code \(status)"
                        throw ForgeError.cli(tool.displayName, String(detail.suffix(500)))
                    }
                    continuation.finish()
                } catch {
                    if process.isRunning { process.terminate() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Command-line arguments per CLI. Claude keeps its isolation flags so the user's personal setup can't leak in.
    static func arguments(tool: Tool, model: String, system: String, outFile: URL?) -> [String] {
        var args: [String]
        switch tool {
        case .claude:
            args = ["-p", "--system-prompt", system,
                    "--no-session-persistence", "--tools", "",
                    "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
                    "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            if !model.isEmpty { args += ["--model", model] }
        case .codex:
            args = ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "--color", "never", "-o", outFile?.path ?? ""]
            if !model.isEmpty { args += ["-m", model] }
            args.append("-")
        case .gemini:
            args = ["-p", "", "-o", "text", "--approval-mode", "plan"]
            if !model.isEmpty { args += ["-m", model] }
        }
        return args
    }

    /// What goes to stdin: the conversation, with the system prompt inlined for CLIs that have no flag for it.
    static func input(tool: Tool, system: String, messages: [ChatMessage]) -> String {
        let text = flatten(messages)
        return tool == .claude ? text : inlineSystem(system, text)
    }

    static func parseClaudeLine(_ line: String) -> ClaudeLine {
        guard let d = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return .notJSON }
        switch obj["type"] as? String {
        case "stream_event":
            if let ev = obj["event"] as? [String: Any], ev["type"] as? String == "content_block_delta",
               let delta = ev["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return .text(text)
            }
            return .other
        case "result":
            return .result(obj["result"] as? String ?? "", isError: obj["is_error"] as? Bool == true)
        default:
            return .other
        }
    }

    /// Reads a pipe to EOF on a GCD thread and resumes asynchronously.
    static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: handle.readDataToEndOfFile()) }
        }
    }

    static func inlineSystem(_ system: String, _ input: String) -> String {
        "<system_instructions>\n\(system)\n</system_instructions>\n\n\(input)"
    }

    /// CLIs take one prompt, so multi-turn conversations are serialized.
    static func flatten(_ messages: [ChatMessage]) -> String {
        guard messages.count > 1, let last = messages.last else { return messages.first?.content ?? "" }
        let turns = messages.dropLast().map { "<\($0.role)>\n\($0.content)\n</\($0.role)>" }.joined(separator: "\n\n")
        return "Earlier conversation:\n<conversation>\n\(turns)\n</conversation>\n\nNew message from the user (respond to this):\n\(last.content)"
    }
}

/// GUI apps don't inherit the shell PATH, so read it once from a login shell.
actor ShellEnvironment {
    static let shared = ShellEnvironment()
    private var cached: [String: String]?

    func load() async -> [String: String] {
        if let cached { return cached }
        var env = ProcessInfo.processInfo.environment
        var path = env["PATH"] ?? "/usr/bin:/bin"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "printf '__PF__%s__PF__' \"$PATH\""]
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        let exited = AsyncStream<Void> { c in p.terminationHandler = { _ in c.yield(); c.finish() } }
        if (try? p.run()) != nil {
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
            let data = await CLIProvider.readToEnd(out.fileHandleForReading)
            for await _ in exited {}
            killer.cancel()
            if let s = String(data: data, encoding: .utf8),
               let a = s.range(of: "__PF__"),
               let b = s.range(of: "__PF__", range: a.upperBound..<s.endIndex) {
                path = String(s[a.upperBound..<b.lowerBound])
            }
        }
        let home = NSHomeDirectory()
        path += ":\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:\(home)/.bun/bin:\(home)/.npm-global/bin"
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        cached = env
        return env
    }

    func locate(_ name: String) async -> URL? {
        Self.find(name, in: await load())
    }

    nonisolated static func find(_ name: String, in env: [String: String]) -> URL? {
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
