import Foundation

/// Anything that can turn (system, messages) into a stream of text.
/// Add a new backend by conforming to this protocol and adding a case to `ProviderKind`.
protocol LLMProvider {
    func stream(system: String, messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error>
}

enum ForgeError: LocalizedError {
    case api(Int, String)
    case network(String)
    case config(String)
    case cli(String, String)

    var errorDescription: String? {
        switch self {
        case let .api(code, msg): return code > 0 ? "API error \(code): \(msg)" : "API error: \(msg)"
        case let .network(msg), let .config(msg): return msg
        case let .cli(tool, msg): return "\(tool) failed: \(msg)"
        }
    }
}

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case claudeCode, codex, geminiCLI, anthropic, openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claudeCode: return "Claude subscription (via Claude Code)"
        case .codex: return "ChatGPT subscription (via Codex CLI)"
        case .geminiCLI: return "Google account (via Gemini CLI)"
        case .anthropic: return "Anthropic API key"
        case .openAICompatible: return "OpenAI-compatible API (OpenAI, OpenRouter, Ollama…)"
        }
    }

    var shortLabel: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        case .anthropic: return "Anthropic API"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }

    var cliName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .geminiCLI: return "gemini"
        default: return nil
        }
    }
}

struct ProviderSettings: Codable, Equatable {
    var kind: ProviderKind = .claudeCode
    var claudeCodeModel = ""
    var codexModel = ""
    var geminiModel = ""
    var anthropicModel = ModelPreset.defaultID
    var openAIBaseURL = "https://api.openai.com/v1"
    var openAIModel = ""

    private static let key = "providerSettings.v1"

    static func load(from defaults: UserDefaults = .standard) -> ProviderSettings {
        guard let d = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(ProviderSettings.self, from: d) else { return ProviderSettings() }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key) }
    }
}

extension ProviderSettings {
    // A new stored property must get a line here too, or it will never be read back.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProviderSettings()
        kind = c.decode(.kind, or: d.kind)
        claudeCodeModel = c.decode(.claudeCodeModel, or: d.claudeCodeModel)
        codexModel = c.decode(.codexModel, or: d.codexModel)
        geminiModel = c.decode(.geminiModel, or: d.geminiModel)
        anthropicModel = c.decode(.anthropicModel, or: d.anthropicModel)
        openAIBaseURL = c.decode(.openAIBaseURL, or: d.openAIBaseURL)
        openAIModel = c.decode(.openAIModel, or: d.openAIModel)
    }
}

enum ProviderFactory {
    /// `key` reads API keys; tests pass a stub so they never touch the real Keychain.
    static func make(_ s: ProviderSettings, key: (Keychain.Account) -> String? = Keychain.load) throws -> LLMProvider {
        switch s.kind {
        case .claudeCode:
            return CLIProvider(tool: .claude, model: s.claudeCodeModel)
        case .codex:
            return CLIProvider(tool: .codex, model: s.codexModel)
        case .geminiCLI:
            return CLIProvider(tool: .gemini, model: s.geminiModel)
        case .anthropic:
            guard let apiKey = key(.anthropic), !apiKey.isEmpty else {
                throw ForgeError.config("Add your Anthropic API key in Settings → Provider.")
            }
            return AnthropicProvider(apiKey: apiKey, model: s.anthropicModel)
        case .openAICompatible:
            guard !s.openAIModel.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ForgeError.config("Set a model ID for the OpenAI-compatible provider in Settings → Provider.")
            }
            return OpenAICompatibleProvider(baseURL: s.openAIBaseURL, apiKey: key(.openAI), model: s.openAIModel)
        }
    }
}
