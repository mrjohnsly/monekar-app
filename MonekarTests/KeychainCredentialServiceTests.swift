#if !SWIFT_PACKAGE && canImport(Security)
import Foundation
import Security
import Testing
@testable import Monekar

@MainActor
struct KeychainCredentialServiceTests {
    @Test func credentialsUseDataProtectionKeychainThroughoutTheirLifecycle() async throws {
        let service = "MonekarTests.\(UUID().uuidString)"
        let credentials = KeychainCredentialService(service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "server-password",
            kSecUseDataProtectionKeychain as String: true,
        ]
        defer { SecItemDelete(query as CFDictionary) }

        #expect(try await credentials.password() == nil)
        try await credentials.setPassword(nil)
        try await credentials.setPassword("test-value")
        #expect(try await credentials.password() == "test-value")

        var lookup = query
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)

        try await credentials.setPassword("updated-value-🔐")
        #expect(try await credentials.password() == "updated-value-🔐")
        try await credentials.setPassword("")
        #expect(try await credentials.password() == "")
        try await credentials.setPassword(nil)
        #expect(try await credentials.password() == nil)
        #expect(SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound)
        try await credentials.setPassword(nil)
    }
}
#endif
