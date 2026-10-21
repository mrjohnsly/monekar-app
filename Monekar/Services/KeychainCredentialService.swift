import Foundation
import Security

struct CredentialError: Error {
    let status: OSStatus
}

@MainActor
final class KeychainCredentialService: CredentialService {
    private let service: String
    private let account = "access-token"

    init(service: String) {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func accessToken() async throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw CredentialError(status: errSecDecode)
        }
        return token
    }

    func setAccessToken(_ token: String?) async throws {
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError(status: status)
            }
            return
        }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialError(status: addStatus) }
        } else if status != errSecSuccess {
            throw CredentialError(status: status)
        }
    }
}
