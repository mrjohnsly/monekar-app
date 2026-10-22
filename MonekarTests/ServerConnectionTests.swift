import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct ServerConnectionTests {
    @Test func normalizesBaseURLAndUsername() throws {
        let configuration = try ServerConnection(
            serverURL: "  http://192.168.1.20:8080/monekar/api/// ",
            username: " admin "
        )

        #expect(configuration.baseURL.absoluteString == "http://192.168.1.20:8080/monekar/api")
        #expect(configuration.username == "admin")
    }

    @Test(arguments: [
        "ftp://server.local",
        "http:///missing-host",
        "http://" + "alice" + ":" + "password" + "@server.local",
        "https://server.local/api?token=secret",
        "https://server.local/api#fragment",
    ])
    func rejectsInvalidServerURLs(_ value: String) {
        do {
            _ = try ServerConnection(serverURL: value, username: "admin")
            Issue.record("Expected invalid URL: \(value)")
        } catch let error as ConnectionConfigurationError {
            #expect(error == .invalidURL)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func healthCheckIsPublicAndUsesNormalizedAPIBasePath() async throws {
        let transport = StubTransport()
        let api = URLSessionAPIService(
            configuration: nil,
            credentials: StubCredentials(password: "secret"),
            transport: transport
        )
        let configuration = try ServerConnection(
            serverURL: "http://server.local/api/",
            username: "alice"
        )

        try await api.verifyConnection(configuration)

        #expect(transport.request?.url?.absoluteString == "http://server.local/api/health")
        #expect(transport.request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func protectedRequestsUseBasicAuthentication() async throws {
        let transport = StubTransport()
        let configuration = try ServerConnection(serverURL: "http://server.local", username: "alice")
        let api = URLSessionAPIService(
            configuration: configuration,
            credentials: StubCredentials(password: "p:a:ss"),
            transport: transport
        )

        _ = try await api.get(path: ["private"])

        #expect(transport.request?.value(forHTTPHeaderField: "Authorization") == "Basic YWxpY2U6cDphOnNz")
        #expect(transport.request?.url?.path == "/private")
    }

    @Test func unauthorizedResponseIsDistinguishable() async throws {
        let transport = StubTransport(statusCode: 401)
        let api = makeAPI(transport: transport)

        do {
            _ = try await api.get(path: ["private"])
            Issue.record("Expected an unauthorized failure")
        } catch let failure as ConnectionFailure {
            #expect(failure == .unauthorized)
        }
    }

    @Test func unreachableHostIsDistinguishable() async throws {
        let transport = StubTransport(error: URLError(.cannotConnectToHost))
        let api = makeAPI(transport: transport)

        do {
            _ = try await api.get(path: ["private"])
            Issue.record("Expected an unreachable failure")
        } catch let failure as ConnectionFailure {
            #expect(failure == .unreachable)
        }
    }

    @Test func localNetworkPermissionFailureIsDistinguishable() async throws {
        let transport = StubTransport(error: URLError(.notConnectedToInternet))
        let api = makeAPI(
            transport: transport,
            configuration: try ServerConnection(serverURL: "http://192.168.1.20", username: "alice")
        )

        do {
            _ = try await api.get(path: ["private"])
            Issue.record("Expected a local-network access failure")
        } catch let failure as ConnectionFailure {
            #expect(failure == .localNetworkAccess)
        }
    }

    @Test func untrustedHTTPSCertificateIsNotBypassed() async throws {
        let transport = StubTransport(error: URLError(.serverCertificateUntrusted))
        let api = makeAPI(
            transport: transport,
            configuration: try ServerConnection(serverURL: "https://server.local", username: "alice")
        )

        do {
            _ = try await api.get(path: ["private"])
            Issue.record("Expected a certificate trust failure")
        } catch let failure as ConnectionFailure {
            #expect(failure == .certificateTrust)
        }
    }

    @Test func connectionVerificationSurfacesTLSFailuresWithoutSendingCredentials() async throws {
        let transport = StubTransport(error: URLError(.serverCertificateUntrusted))
        let api = makeAPI(
            transport: transport,
            configuration: try ServerConnection(serverURL: "https://server.local", username: "alice")
        )

        do {
            try await api.verifyConnection(api.configuration)
            Issue.record("Expected a certificate trust failure")
        } catch let failure as ConnectionFailure {
            #expect(failure == .certificateTrust)
        }
        #expect(transport.request?.url?.path == "/health")
        #expect(transport.request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func mediaOnAnotherOriginDoesNotReceiveCredentials() async throws {
        let transport = StubTransport()
        let api = makeAPI(transport: transport)

        _ = try await api.get(mediaReference: "https://media.example/file.jpg")

        #expect(transport.request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func setupVerifiesBeforeSavingAndKeepsPasswordInCredentialService() async throws {
        let transport = StubTransport()
        let credentials = StubCredentials()
        let metadata = StubMetadata()
        let configuration = try ServerConnection(serverURL: "http://server.local", username: "alice")
        let api = URLSessionAPIService(configuration: nil, credentials: credentials, transport: transport)
        let services = AppServices(api: api, credentials: credentials, connectionMetadata: metadata)
        let model = ConnectionViewModel(services: services)
        model.serverURL = "http://server.local/"
        model.username = "alice"
        model.password = "secret"

        await model.verifyAndSave()

        #expect(model.state == .connected)
        #expect(metadata.configuration == configuration)
        #expect(credentials.storedPassword == "secret")
        #expect(api.baseURL == configuration.baseURL)
        #expect(model.password.isEmpty)
    }

    @Test func failedHealthCheckDoesNotSaveCredentialsOrMetadata() async throws {
        let transport = StubTransport(error: URLError(.cannotConnectToHost))
        let credentials = StubCredentials()
        let metadata = StubMetadata()
        let api = URLSessionAPIService(configuration: nil, credentials: credentials, transport: transport)
        let model = ConnectionViewModel(
            services: AppServices(api: api, credentials: credentials, connectionMetadata: metadata)
        )
        model.serverURL = "http://server.local"
        model.username = "alice"
        model.password = "secret"

        await model.verifyAndSave()

        #expect(model.state == .failed(.unreachable))
        #expect(metadata.configuration == nil)
        #expect(credentials.storedPassword == nil)
    }

    @Test func keychainFailurePreservesTheOperatingSystemStatus() {
        #expect(
            ConnectionFailure.credentialStorage(-34018).message
                == "Monekar could not save the password in Keychain (error -34018)."
        )
    }

    @Test func metadataPersistsOnlyConnectionConfiguration() throws {
        let suiteName = "ServerConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = UserDefaultsConnectionMetadataService(defaults: defaults)
        let configuration = try ServerConnection(
            serverURL: "http://server.local/api",
            username: "alice"
        )

        try metadata.save(configuration)

        #expect(metadata.configuration == configuration)
        #expect(defaults.data(forKey: "server-connection") != nil)
    }

    private func makeAPI(
        transport: StubTransport,
        configuration: ServerConnection? = try? ServerConnection(
            serverURL: "http://server.local",
            username: "alice"
        )
    ) -> URLSessionAPIService {
        URLSessionAPIService(
            configuration: configuration,
            credentials: StubCredentials(password: "secret"),
            transport: transport
        )
    }
}

@MainActor
private final class StubTransport: HTTPTransport {
    let statusCode: Int
    let error: (any Error)?
    private(set) var request: URLRequest?

    init(statusCode: Int = 200, error: (any Error)? = nil) {
        self.statusCode = statusCode
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

@MainActor
private final class StubCredentials: CredentialService {
    var storedPassword: String?

    init(password: String? = nil) {
        storedPassword = password
    }

    func password() async throws -> String? {
        storedPassword
    }

    func setPassword(_ password: String?) async throws {
        storedPassword = password
    }
}

@MainActor
private final class StubMetadata: ConnectionMetadataService {
    var configuration: ServerConnection?

    func save(_ configuration: ServerConnection) throws {
        self.configuration = configuration
    }

    func remove() throws {
        configuration = nil
    }
}
