import Foundation
import Security

@MainActor
final class KeychainCredentialService: CredentialService {
    private let service: String
    private let account = "server-password"

    init(service: String) {
        self.service = service
    }

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    func password() async throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError(status: Int(status)) }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw CredentialError(status: Int(errSecDecode))
        }
        return password
    }

    func setPassword(_ password: String?) async throws {
        guard let password else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError(status: Int(status))
            }
            return
        }
        let attributes = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            #if os(iOS)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #endif
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialError(status: Int(addStatus)) }
        } else if status != errSecSuccess {
            throw CredentialError(status: Int(status))
        }
    }
}
