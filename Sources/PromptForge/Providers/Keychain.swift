import Foundation
import Security

/// API keys live only here (service com.dvd90.PromptForge). OS glue: excluded from the coverage gate.
enum Keychain {
    enum Account: String {
        case anthropic = "anthropic-api-key"
        case openAI = "openai-compatible-api-key"
    }

    private static let service = "com.dvd90.PromptForge"

    private static func base(_ a: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: a.rawValue]
    }

    static func save(_ value: String, for a: Account) {
        SecItemDelete(base(a) as CFDictionary)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        var item = base(a)
        item[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(_ a: Account) -> String? {
        var q = base(a)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
