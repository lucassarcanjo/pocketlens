import Foundation
import Security

/// Read/write API keys to the macOS Keychain.
///
/// One service per provider: `pocketlens.<provider>` (e.g. `pocketlens.anthropic`).
/// Items use `kSecAttrAccessibleWhenUnlocked` — the key is available when the
/// user is logged in and the device is unlocked, never accessible to other
/// users on a shared mac.
public struct KeychainStore: Sendable {

    public enum KeychainError: Error, Equatable, Sendable {
        case unhandledError(status: OSStatus)
        case dataConversionError
        case notFound
    }

    public static let anthropicService = "pocketlens.anthropic"
    public static let mistralService   = "pocketlens.mistral"

    public let service: String
    public let account: String

    public init(service: String, account: String = "default") {
        self.service = service
        self.account = account
    }

    public static let anthropic = KeychainStore(service: anthropicService)
    public static let mistral   = KeychainStore(service: mistralService)

    public func read() throws -> String? {
        var query: [String: Any] = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let s = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionError
            }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }

    public func write(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
        default:
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
    }
}
