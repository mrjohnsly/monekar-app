import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct AppFoundationTests {
    private let serverURL = URL(string: "https://example.invalid")!

    @Test func launchStartsAtRootAndNavigationReturnsHome() {
        let coordinator = AppCoordinator(services: services())
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.home.state == .idle)
        coordinator.showConnection()
        coordinator.showConnection()
        #expect(coordinator.path == [.connection])
        coordinator.pop()
        coordinator.pop()
        #expect(coordinator.path.isEmpty)
        coordinator.showConnection()
        coordinator.reset()
        #expect(coordinator.path.isEmpty)
    }

    @Test func windowsHaveIndependentNavigation() {
        let first = AppCoordinator(services: services())
        let second = AppCoordinator(services: services())
        first.showConnection()
        #expect(second.path.isEmpty)
    }

    @Test func unconfiguredLaunchShowsEmptyState() async {
        let model = HomeViewModel(services: services())
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func configuredLaunchLoadsConnection() async {
        let credentials = StubCredentials(password: "test-value")
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        await model.load()
        #expect(model.state == .loaded(ConnectionSummary(serverURL: serverURL, hasCredential: true)))
    }

    @Test(arguments: [nil, ""])
    func missingCredentialRequiresSignIn(password: String?) async {
        let model = HomeViewModel(services: services(
            url: serverURL, credentials: StubCredentials(password: password)
        ))
        await model.load()
        #expect(model.state == .loaded(ConnectionSummary(serverURL: serverURL, hasCredential: false)))
    }

    @Test func credentialFailureCanBeRetried() async {
        let credentials = StubCredentials()
        credentials.error = StubError.unavailable
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        await model.load()
        #expect(model.state == .failed)
        credentials.error = nil
        await model.load()
        #expect(model.state == .loaded(ConnectionSummary(serverURL: serverURL, hasCredential: false)))
    }

    @Test func loadingIsObservableAndDuplicateLoadsAreIgnored() async {
        let credentials = StubCredentials()
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        credentials.onRead = {
            #expect(model.state == .loading)
            await model.load()
        }
        await model.load()
        #expect(credentials.readCount == 1)
    }

    @Test func cancelledLoadRestoresPreviousState() async {
        let credentials = StubCredentials()
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        credentials.error = CancellationError()
        await model.load()
        #expect(model.state == .idle)
        credentials.error = nil
        await model.load()
        let loaded = model.state
        credentials.error = CancellationError()
        await model.load()
        #expect(model.state == loaded)
    }

    private func services(
        url: URL? = nil, credentials: StubCredentials = StubCredentials()
    ) -> AppServices {
        let configuration = url.flatMap { try? ServerConnection(baseURL: $0, username: "user") }
        let metadata = StubMetadata(configuration: configuration)
        let api = StubAPI(configuration: configuration)
        return AppServices(api: api, credentials: credentials, connectionMetadata: metadata)
    }
}

private enum StubError: Error {
    case unavailable
}

@MainActor
private final class StubAPI: APIService {
    private(set) var configuration: ServerConnection?

    init(configuration: ServerConnection?) {
        self.configuration = configuration
    }

    var baseURL: URL? { configuration?.baseURL }

    func configure(_ configuration: ServerConnection?) {
        self.configuration = configuration
    }

    func verifyConnection(_ configuration: ServerConnection?) async throws {}

    func get(path: [String]) async throws -> Data {
        Data()
    }

    func get(mediaReference: String) async throws -> Data {
        Data()
    }
}

@MainActor
private final class StubCredentials: CredentialService {
    var storedPassword: String?
    var error: (any Error)?
    var onRead: (() async -> Void)?
    var readCount = 0

    init(password: String? = nil) {
        self.storedPassword = password
    }

    func password() async throws -> String? {
        readCount += 1
        await onRead?()
        if let error { throw error }
        return storedPassword
    }

    func setPassword(_ password: String?) async throws {
        storedPassword = password
    }
}

@MainActor
private final class StubMetadata: ConnectionMetadataService {
    var configuration: ServerConnection?

    init(configuration: ServerConnection?) {
        self.configuration = configuration
    }

    func save(_ configuration: ServerConnection) throws {
        self.configuration = configuration
    }

    func remove() throws {
        configuration = nil
    }
}
