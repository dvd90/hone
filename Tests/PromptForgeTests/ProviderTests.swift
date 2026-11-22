import XCTest
@testable import PromptForge

/// Providers without real network calls or CLIs: HTTP goes through a URLProtocol stub,
/// and the CLI provider runs small fake `claude` / `codex` / `gemini` scripts from a temp folder.
final class ProviderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PF-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        StubProtocol.handler = nil
    }

    private let messages = [ChatMessage(role: "user", content: "hi")]

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var out = ""
        for try await chunk in stream { out += chunk }
        return out
    }

    // MARK: Errors, kinds, settings, factory

    func testErrorDescriptions() {
        XCTAssertEqual(ForgeError.api(401, "bad key").errorDescription, "API error 401: bad key")
        XCTAssertEqual(ForgeError.api(0, "stream").errorDescription, "API error: stream")
        XCTAssertEqual(ForgeError.network("offline").errorDescription, "offline")
        XCTAssertEqual(ForgeError.config("set it").errorDescription, "set it")
        XCTAssertEqual(ForgeError.cli("Codex", "boom").errorDescription, "Codex failed: boom")
    }

    func testProviderKinds() {
        for kind in ProviderKind.allCases {
            XCTAssertEqual(kind.id, kind.rawValue)
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.shortLabel.isEmpty)
        }
        XCTAssertEqual(ProviderKind.allCases.compactMap(\.cliName), ["claude", "codex", "gemini"])
    }

    func testProviderSettingsPersistInDefaults() throws {
        let suite = "PF-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ProviderSettings.load(from: defaults), ProviderSettings())
        var s = ProviderSettings()
        s.kind = .codex; s.codexModel = "o5"
        s.save(to: defaults)
        XCTAssertEqual(ProviderSettings.load(from: defaults), s)
        defaults.set(Data("not json".utf8), forKey: "providerSettings.v1")
        XCTAssertEqual(ProviderSettings.load(from: defaults), ProviderSettings())
    }

    func testFactory() throws {
        var s = ProviderSettings()
        let noKey: (Keychain.Account) -> String? = { _ in nil }
        let keys: (Keychain.Account) -> String? = { $0 == .anthropic ? "sk-test" : "or-key" }

        s.kind = .claudeCode; s.claudeCodeModel = "opus"
        let claude = try XCTUnwrap(try ProviderFactory.make(s, key: noKey) as? CLIProvider)
        XCTAssertEqual(claude.tool, .claude); XCTAssertEqual(claude.model, "opus")
        s.kind = .codex
        XCTAssertEqual((try ProviderFactory.make(s, key: noKey) as? CLIProvider)?.tool, .codex)
        s.kind = .geminiCLI
        XCTAssertEqual((try ProviderFactory.make(s, key: noKey) as? CLIProvider)?.tool, .gemini)

        s.kind = .anthropic
        XCTAssertThrowsError(try ProviderFactory.make(s, key: noKey))
        XCTAssertEqual((try ProviderFactory.make(s, key: keys) as? AnthropicProvider)?.apiKey, "sk-test")

        s.kind = .openAICompatible; s.openAIModel = "  "
        XCTAssertThrowsError(try ProviderFactory.make(s, key: keys))
        s.openAIModel = "llama"
        let openAI = try XCTUnwrap(try ProviderFactory.make(s, key: keys) as? OpenAICompatibleProvider)
        XCTAssertEqual(openAI.apiKey, "or-key"); XCTAssertEqual(openAI.model, "llama")
    }

    // MARK: HTTP requests and stream parsing

    func testAnthropicRequestAndExtract() throws {
        let req = AnthropicProvider.request(apiKey: "sk", model: "claude-x", system: "sys", messages: messages, maxTokens: 42)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual(body["max_tokens"] as? Int, 42)

        XCTAssertEqual(try AnthropicProvider.extract(["type": "content_block_delta", "delta": ["type": "text_delta", "text": "Hi"]]), "Hi")
        XCTAssertNil(try AnthropicProvider.extract(["type": "content_block_delta", "delta": ["type": "input_json_delta"]]))
        XCTAssertNil(try AnthropicProvider.extract(["type": "message_start"]))
        XCTAssertThrowsError(try AnthropicProvider.extract(["type": "error", "error": ["message": "overloaded"]])) {
            XCTAssertEqual($0.localizedDescription, "API error: overloaded")
        }
        XCTAssertThrowsError(try AnthropicProvider.extract(["type": "error"]))
    }

    func testOpenAIRequestAndExtract() throws {
        let req = try XCTUnwrap(OpenAICompatibleProvider.request(baseURL: " https://openrouter.ai/api/v1// ", apiKey: "k",
                                                                 model: "m", system: "sys", messages: messages))
        XCTAssertEqual(req.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Title"), "Hone")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual((body["messages"] as? [[String: String]])?.first?["role"], "system")

        let local = try XCTUnwrap(OpenAICompatibleProvider.request(baseURL: "http://localhost:11434/v1", apiKey: nil,
                                                                   model: "m", system: "s", messages: messages))
        XCTAssertNil(local.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(local.value(forHTTPHeaderField: "X-Title"))
        for bad in ["localhost:11434/v1", "", "ftp://example.com"] {
            XCTAssertNil(OpenAICompatibleProvider.request(baseURL: bad, apiKey: nil, model: "m", system: "s", messages: messages), bad)
        }
        XCTAssertEqual(OpenAICompatibleProvider.presets.count, 4)

        XCTAssertEqual(try OpenAICompatibleProvider.extract(["choices": [["delta": ["content": "Hi"]]]]), "Hi")
        XCTAssertNil(try OpenAICompatibleProvider.extract(["choices": []]))
        XCTAssertThrowsError(try OpenAICompatibleProvider.extract(["error": ["message": "quota"]]))
        XCTAssertThrowsError(try OpenAICompatibleProvider.extract(["error": [:] as [String: Any]]))
    }

    func testSSEErrorMessage() {
        XCTAssertEqual(SSE.errorMessage(from: Data(#"{"error":{"message":"bad key"}}"#.utf8)), "bad key")
        XCTAssertEqual(SSE.errorMessage(from: Data(#"{"error":"nope"}"#.utf8)), "nope")
        XCTAssertEqual(SSE.errorMessage(from: Data(#"{"message":"gone"}"#.utf8)), "gone")
        XCTAssertEqual(SSE.errorMessage(from: Data("plain text".utf8)), "plain text")
        XCTAssertEqual(SSE.errorMessage(from: Data([0xFF, 0xFE])), "Unknown error")
    }

    // MARK: HTTP streaming through a stubbed URLSession

    private func stubbedSession(status: Int, body: String, httpResponse: Bool = true) -> URLSession {
        StubProtocol.handler = { request in
            let response: URLResponse = httpResponse
                ? HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                : URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (response, Data(body.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    func testAnthropicStreamsTextUntilDone() async throws {
        let body = """
        event: message_start
        data: {"type":"message_start"}
        data: not json
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":""}}
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}
        data: [DONE]
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ignored"}}
        """
        let provider = AnthropicProvider(apiKey: "k", model: "m", session: stubbedSession(status: 200, body: body))
        let text = try await collect(provider.stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(text, "Hello world")
    }

    func testOpenAIStreamAndInvalidBaseURL() async throws {
        let body = #"data: {"choices":[{"delta":{"content":"OK"}}]}"#
        let ok = OpenAICompatibleProvider(baseURL: "https://example.com/v1", apiKey: nil, model: "m",
                                          session: stubbedSession(status: 200, body: body))
        let text = try await collect(ok.stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(text, "OK")

        let bad = OpenAICompatibleProvider(baseURL: "not a url", apiKey: nil, model: "m")
        do { _ = try await collect(bad.stream(system: "s", messages: messages, maxTokens: 10)); XCTFail("expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Invalid base URL")) }
    }

    func testStreamErrors() async throws {
        let unauthorized = AnthropicProvider(apiKey: "k", model: "m",
                                             session: stubbedSession(status: 401, body: #"{"error":{"message":"invalid x-api-key"}}"#))
        do { _ = try await collect(unauthorized.stream(system: "s", messages: messages, maxTokens: 10)); XCTFail("expected error") }
        catch { XCTAssertEqual(error.localizedDescription, "API error 401: invalid x-api-key") }

        let midStream = AnthropicProvider(apiKey: "k", model: "m",
                                          session: stubbedSession(status: 200, body: #"data: {"type":"error","error":{"message":"overloaded"}}"#))
        do { _ = try await collect(midStream.stream(system: "s", messages: messages, maxTokens: 10)); XCTFail("expected error") }
        catch { XCTAssertEqual(error.localizedDescription, "API error: overloaded") }

        let notHTTP = AnthropicProvider(apiKey: "k", model: "m", session: stubbedSession(status: 200, body: "", httpResponse: false))
        do { _ = try await collect(notHTTP.stream(system: "s", messages: messages, maxTokens: 10)); XCTFail("expected error") }
        catch { XCTAssertEqual(error.localizedDescription, "No response from server.") }
    }

    func testStoppingEarlyCancelsTheRequest() async throws {
        let body = (1...50).map { #"data: {"choices":[{"delta":{"content":"x\#($0)"}}]}"# }.joined(separator: "\n")
        let provider = OpenAICompatibleProvider(baseURL: "https://example.com/v1", apiKey: nil, model: "m",
                                                session: stubbedSession(status: 200, body: body))
        for try await chunk in provider.stream(system: "s", messages: messages, maxTokens: 10) {
            XCTAssertEqual(chunk, "x1")
            break
        }
    }

    // MARK: CLI provider

    func testCLIArgumentsAndInput() {
        let claude = CLIProvider.arguments(tool: .claude, model: "opus", system: "SYS", outFile: nil)
        for flag in ["--tools", "--setting-sources", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"] {
            XCTAssertTrue(claude.contains(flag), flag)   // isolation flags keep the user's Claude Code setup out
        }
        XCTAssertFalse(claude.contains("--bare"))      // --bare would disable subscription login
        XCTAssertEqual(Array(claude.suffix(2)), ["--model", "opus"])
        XCTAssertFalse(CLIProvider.arguments(tool: .claude, model: "", system: "SYS", outFile: nil).contains("--model"))

        let out = URL(fileURLWithPath: "/tmp/codex.txt")
        let codex = CLIProvider.arguments(tool: .codex, model: "o5", system: "SYS", outFile: out)
        XCTAssertTrue(codex.contains("/tmp/codex.txt")); XCTAssertTrue(codex.contains("read-only"))
        XCTAssertEqual(Array(codex.suffix(3)), ["-m", "o5", "-"])
        XCTAssertEqual(CLIProvider.arguments(tool: .gemini, model: "pro", system: "SYS", outFile: nil).suffix(2), ["-m", "pro"])
        XCTAssertEqual(CLIProvider.arguments(tool: .gemini, model: "", system: "SYS", outFile: nil).last, "plan")

        XCTAssertEqual(CLIProvider.input(tool: .claude, system: "SYS", messages: messages), "hi")
        XCTAssertTrue(CLIProvider.input(tool: .codex, system: "SYS", messages: messages).hasPrefix("<system_instructions>\nSYS"))
        for tool in [CLIProvider.Tool.claude, .codex, .gemini] { XCTAssertFalse(tool.displayName.isEmpty) }
    }

    func testParseClaudeLine() {
        XCTAssertEqual(CLIProvider.parseClaudeLine("warning: not json"), .notJSON)
        XCTAssertEqual(CLIProvider.parseClaudeLine(#"{"type":"system"}"#), .other)
        XCTAssertEqual(CLIProvider.parseClaudeLine(#"{"type":"stream_event","event":{"type":"message_start"}}"#), .other)
        XCTAssertEqual(CLIProvider.parseClaudeLine(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#), .text("Hi"))
        XCTAssertEqual(CLIProvider.parseClaudeLine(#"{"type":"result","result":"Done"}"#), .result("Done", isError: false))
        XCTAssertEqual(CLIProvider.parseClaudeLine(#"{"type":"result","is_error":true}"#), .result("", isError: true))
    }

    /// Writes an executable fake CLI and returns a provider whose PATH only sees the temp folder (plus system tools).
    private func fake(_ tool: CLIProvider.Tool, mode: String = "", script: String) throws -> CLIProvider {
        let url = dir.appendingPathComponent(tool.rawValue)
        try ("#!/bin/bash\ncat > /dev/null\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return CLIProvider(tool: tool, model: "", environment: ["PATH": "\(dir.path):/usr/bin:/bin", "FAKE_MODE": mode])
    }

    private static let claudeScript = #"""
    case "$FAKE_MODE" in
      stream)
        echo 'not json'
        echo '{"type":"system"}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}}}'
        echo '{"type":"result","result":"Hello"}' ;;
      result) echo '{"type":"result","result":"Only the result"}' ;;
      error) echo '{"type":"result","is_error":true,"result":"Not logged in"}' ;;
      errorEmpty) echo '{"type":"result","is_error":true}' ;;
      stderrExit) echo "boom" >&2; exit 3 ;;
      stdoutExit) echo "plain failure"; exit 2 ;;
      silentExit) exit 4 ;;
      sleep) sleep 10 ;;
    esac
    """#

    private func cliError(_ provider: CLIProvider) async -> String? {
        do { _ = try await collect(provider.stream(system: "s", messages: messages, maxTokens: 10)); return nil }
        catch { return error.localizedDescription }
    }

    func testClaudeCLIStreamsDeltasAndResultFallback() async throws {
        let streaming = try fake(.claude, mode: "stream", script: Self.claudeScript)
        let streamed = try await collect(streaming.stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(streamed, "Hello")   // deltas only; the final result isn't repeated
        let resultOnly = try fake(.claude, mode: "result", script: Self.claudeScript)
        let fallback = try await collect(resultOnly.stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(fallback, "Only the result")
    }

    func testClaudeCLIErrors() async throws {
        let notLoggedIn = await cliError(try fake(.claude, mode: "error", script: Self.claudeScript))
        XCTAssertEqual(notLoggedIn, "Claude Code failed: Not logged in")
        let unknown = await cliError(try fake(.claude, mode: "errorEmpty", script: Self.claudeScript))
        XCTAssertEqual(unknown, "Claude Code failed: unknown error")
        let stderr = await cliError(try fake(.claude, mode: "stderrExit", script: Self.claudeScript))
        XCTAssertEqual(stderr, "Claude Code failed: boom")
        let stdout = await cliError(try fake(.claude, mode: "stdoutExit", script: Self.claudeScript))
        XCTAssertEqual(stdout, "Claude Code failed: plain failure")
        let silent = await cliError(try fake(.claude, mode: "silentExit", script: Self.claudeScript))
        XCTAssertEqual(silent, "Claude Code failed: exit code 4")
        let missing = CLIProvider(tool: .claude, model: "", environment: ["PATH": "/nonexistent-\(UUID().uuidString)"])
        let notFound = await cliError(missing)
        XCTAssertTrue(notFound?.contains("Couldn't find the `claude` command") == true)
    }

    func testCodexReadsItsOutputFile() async throws {
        let script = """
        out=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; shift; fi; shift; done
        echo "progress noise"
        printf "Codex answer" > "$out"
        """
        let text = try await collect(try fake(.codex, script: script).stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(text, "Codex answer")
    }

    func testGeminiStreamsLines() async throws {
        let text = try await collect(try fake(.gemini, script: "echo one\necho two").stream(system: "s", messages: messages, maxTokens: 10))
        XCTAssertEqual(text, "one\ntwo\n")
    }

    func testCancellingStopsTheCLI() async throws {
        let provider = try fake(.claude, mode: "sleep", script: Self.claudeScript)
        let started = Date()
        let task = Task { _ = try? await collect(provider.stream(system: "s", messages: messages, maxTokens: 10)) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)   // the 10 s sleep was terminated
    }

    func testShellEnvironment() async {
        let env = await ShellEnvironment.shared.load()
        XCTAssertEqual(env["NO_COLOR"], "1")
        XCTAssertTrue(env["PATH"]?.contains("/.local/bin") == true)
        let again = await ShellEnvironment.shared.load()
        XCTAssertEqual(again, env)   // cached
        let sh = await ShellEnvironment.shared.locate("sh")
        XCTAssertNotNil(sh)
        XCTAssertNil(ShellEnvironment.find("definitely-not-a-command-\(UUID().uuidString)", in: env))
    }
}

/// Serves canned responses to URLSession so HTTP providers run without the network.
final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
