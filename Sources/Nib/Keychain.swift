import Foundation
import Security

/// Stores the API key in the login Keychain.
///
/// The key deliberately never reaches the web layer: completions are requested
/// by the WebView but performed here, so a bug or injected script in the page
/// cannot read it.
enum Keychain {
    private static let service = "app.nib.apikey"
    private static let account = "anthropic"

    static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func writeAPIKey(_ key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete first so this is an upsert; SecItemUpdate fails when absent.
        SecItemDelete(base as CFDictionary)

        guard !key.isEmpty else { return true }
        var attributes = base
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
