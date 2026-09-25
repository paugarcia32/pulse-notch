import Foundation
import Security

enum CredentialAccount: String, CaseIterable, Sendable {
    case typeSafe = "typesafe"
    case openRouter = "openrouter"
    case layaEndpoint = "laya-endpoint"
    case localLanguageEndpoint = "local-language-endpoint"

    var displayName: String {
        switch self {
        case .typeSafe: "TypeSafe API key"
        case .openRouter: "OpenRouter API key"
        case .layaEndpoint: "Laya service key"
        case .localLanguageEndpoint: "Local model server key"
        }
    }
}

enum CredentialStoreError: Error, Equatable {
    case keychain(OSStatus)

    var userMessage: String {
        switch self {
        case .keychain(let status):
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }
}

protocol CredentialStore: Sendable {
    func secret(for account: CredentialAccount) throws -> String?
    func setSecret(_ secret: String, for account: CredentialAccount) throws
    func removeSecret(for account: CredentialAccount) throws
}

/// Stores provider credentials as generic passwords in the login Keychain. They are
/// never written to preferences, logs, or the agent database.
struct KeychainCredentialStore: CredentialStore {
    let service: String

    init(service: String = "dev.paugarcia32.PulseNotch.AIAgent") {
        self.service = service
    }

    func secret(for account: CredentialAccount) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).map { String(decoding: $0, as: UTF8.self) }
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status)
        }
    }

    func setSecret(_ secret: String, for account: CredentialAccount) throws {
        let data = Data(secret.utf8)
        let update = SecItemUpdate(baseQuery(for: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery(for: account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecAttrLabel as String] = "Pulse Notch – \(account.displayName)"
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        default:
            throw CredentialStoreError.keychain(update)
        }
    }

    func removeSecret(for account: CredentialAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }
    }

    private func baseQuery(for account: CredentialAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }
}
