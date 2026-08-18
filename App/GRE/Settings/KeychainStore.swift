import Foundation
import Security

/// The OpenRouter API key, in the Keychain.
///
/// Not UserDefaults: that is a plist in the app container, readable from a
/// backup. The key is a bearer credential that can spend the user's money.
enum KeychainStore {

    private static let service = "dev.soyeb.GRE"
    private static let account = "openrouter-api-key"

    static var apiKey: String? {
        get {
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
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)

            guard let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return }

            var insert = base
            insert[kSecValueData as String] = Data(value.utf8)
            // The key is only ever needed while the app is in use, and should
            // never ride along to a new device in a backup.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static var hasKey: Bool { apiKey != nil }
}
