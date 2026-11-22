import Foundation

/// Server-sent-events helper shared by the HTTP providers.
enum SSE {
    static func stream(_ request: URLRequest, session: URLSession = .shared,
                       extract: @escaping ([String: Any]) throws -> String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ForgeError.network("No response from server.") }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        throw ForgeError.api(http.statusCode, errorMessage(from: data))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        if let text = try extract(obj), !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
            if let msg = obj["message"] as? String { return msg }
        }
        return String(data: data, encoding: .utf8)?.prefix(400).description ?? "Unknown error"
    }

    static func failed(_ error: Error) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

struct AnthropicProvider: LLMProvider {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    func stream(system: String, messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        SSE.stream(Self.request(apiKey: apiKey, model: model, system: system, messages: messages, maxTokens: maxTokens),
                   session: session, extract: Self.extract)
    }

    static func request(apiKey: String, model: String, system: String, messages: [ChatMessage], maxTokens: Int) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func extract(_ obj: [String: Any]) throws -> String? {
        switch obj["type"] as? String {
        case "content_block_delta":
            let delta = obj["delta"] as? [String: Any]
            return delta?["type"] as? String == "text_delta" ? delta?["text"] as? String : nil
        case "error":
            let err = obj["error"] as? [String: Any]
            throw ForgeError.api(0, err?["message"] as? String ?? "Stream error")
        default:
            return nil
        }
    }
}

/// Works with OpenAI, OpenRouter, Groq, Together, Ollama, LM Studio — anything exposing /chat/completions.
struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: String
    let apiKey: String?
    let model: String
    var session: URLSession = .shared

    static let presets: [(name: String, url: String)] = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("OpenRouter", "https://openrouter.ai/api/v1"),
        ("Ollama (local)", "http://localhost:11434/v1"),
        ("LM Studio (local)", "http://localhost:1234/v1"),
    ]

    func stream(system: String, messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        guard let req = Self.request(baseURL: baseURL, apiKey: apiKey, model: model, system: system, messages: messages) else {
            return SSE.failed(ForgeError.config("Invalid base URL: \(baseURL). Use a full http(s) address, e.g. https://api.openai.com/v1"))
        }
        return SSE.stream(req, session: session, extract: Self.extract)
    }

    /// Nil when the base URL isn't an http(s) address with a host.
    static func request(baseURL: String, apiKey: String?, model: String, system: String, messages: [ChatMessage]) -> URLRequest? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if base.contains("openrouter.ai") { req.setValue("Hone", forHTTPHeaderField: "X-Title") }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [["role": "system", "content": system]] + messages.map { ["role": $0.role, "content": $0.content] },
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func extract(_ obj: [String: Any]) throws -> String? {
        if let err = obj["error"] as? [String: Any] {
            throw ForgeError.api(0, err["message"] as? String ?? "Stream error")
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }
}
