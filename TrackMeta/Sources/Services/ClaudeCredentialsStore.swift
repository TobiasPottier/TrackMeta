import Foundation
import Security

// Reads the OAuth access token that the Claude Code CLI stores in the macOS
// Keychain under service "Claude Code-credentials".
//
// The stored value is a JSON string that looks roughly like:
//   { "claudeAiOauth": { "accessToken": "...", "refreshToken": "...", ... } }
//
// First-ever read triggers a one-time macOS permission prompt; the user clicks
// "Always Allow" and subsequent reads are silent.
enum ClaudeCredentialsStore {
    private static let service = "Claude Code-credentials"

    static func readAccessToken() -> String? {
        guard let json = readKeychainValue() else { return nil }
        return extractAccessToken(fromJSON: json)
    }

    private static func readKeychainValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    private static func extractAccessToken(fromJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
