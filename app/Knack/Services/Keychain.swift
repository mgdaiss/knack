import Foundation
import KnackCore
import Security

/// Generic-password Keychain items for this app. The only secrets the app holds are the Knack
/// session tokens (and, in DEBUG builds, a developer's own OpenRouter key).
enum Keychain {
    static let service = "com.knack.app"

    static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Knack Cloud session tokens, in the Keychain only.
final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    private let account = "knack-session"

    func load() -> StoredSession? {
        Keychain.read(account).flatMap { try? JSONDecoder().decode(StoredSession.self, from: $0) }
    }

    func save(_ session: StoredSession) {
        if let data = try? JSONEncoder().encode(session) { Keychain.write(data, account: account) }
    }

    func clear() {
        Keychain.delete(account)
    }
}

#if DEBUG
/// A developer's own OpenRouter key for `DirectOpenRouterProvider`. DEBUG builds only.
enum DeveloperKeyStore {
    private static let account = "openrouter-dev-key"

    static var key: String? {
        Keychain.read(account).map { String(decoding: $0, as: UTF8.self) }
    }

    static func set(_ key: String?) {
        if let key, !key.isEmpty { Keychain.write(Data(key.utf8), account: account) } else { Keychain.delete(account) }
    }
}
#endif
