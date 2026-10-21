import Foundation

struct ServerConnection: Codable, Equatable {
    let baseURL: URL
    let username: String

    init(serverURL: String, username: String) throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty, !normalizedUsername.contains(":"),
              normalizedUsername.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ConnectionConfigurationError.missingUsername
        }
        guard let components = Self.normalizedComponents(serverURL),
              let baseURL = components.url else {
            throw ConnectionConfigurationError.invalidURL
        }
        self.baseURL = baseURL
        self.username = normalizedUsername
    }

    init(baseURL: URL, username: String) throws {
        try self.init(serverURL: baseURL.absoluteString, username: username)
    }

    private static func normalizedComponents(_ value: String) -> URLComponents? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            return nil
        }
        components.scheme = scheme
        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        return components
    }
}

enum ConnectionConfigurationError: Error, Equatable {
    case invalidURL
    case missingUsername
}

struct CredentialError: Error {
    let status: Int
}

enum ConnectionFailure: Error, Equatable {
    case invalidURL
    case missingUsername
    case missingPassword
    case unauthorized
    case unreachable
    case localNetworkAccess
    case certificateTrust
    case serverRejected(Int)
    case invalidResponse
    case storageFailure
    case credentialStorage(Int)

    var message: String {
        switch self {
        case .invalidURL:
            "Enter a valid HTTP or HTTPS server URL without credentials, query, or fragment."
        case .missingUsername:
            "Enter your server username."
        case .missingPassword:
            "Enter your server password."
        case .unauthorized:
            "The server rejected these credentials. Check your username and password, then sign in again."
        case .unreachable:
            "The server could not be reached. Check its address and that your device is on the same network or Tailscale."
        case .localNetworkAccess:
            "Local-network access may be disabled. Allow Monekar in Settings > Privacy & Security > Local Network, then try again."
        case .certificateTrust:
            "The HTTPS certificate could not be verified. Check the reverse proxy certificate; Monekar will not bypass certificate validation."
        case .serverRejected(let status):
            "The server returned HTTP \(status). Check the server address and try again."
        case .invalidResponse:
            "The server returned an invalid response. Check that this is a monekar-server URL."
        case .storageFailure:
            "Monekar could not save the password in Keychain. Try again."
        case .credentialStorage(let status):
            "Monekar could not save the password in Keychain (error \(status))."
        }
    }
}

@MainActor
final class UserDefaultsConnectionMetadataService: ConnectionMetadataService {
    private let defaults: UserDefaults
    private let key = "server-connection"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: ServerConnection? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerConnection.self, from: data)
    }

    func save(_ configuration: ServerConnection) throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }

    func remove() throws {
        defaults.removeObject(forKey: key)
    }
}
