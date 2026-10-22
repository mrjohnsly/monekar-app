import Foundation
import Observation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct AppFoundationTests {
    private let serverURL = URL(string: "https://example.invalid")!

    @Test func launchConnectionStateStartsIdle() {
        let model = HomeViewModel(services: services())
        #expect(model.state == .idle)
    }

    @Test func connectionRevisionIsObservableAcrossSharedWindows() async {
        let firstWindow = services()
        let secondWindow = firstWindow
        let separateApp = services()
        let originalRevision = firstWindow.connectionRevision
        let separateRevision = separateApp.connectionRevision
        await confirmation("Shared windows invalidate browsing state") { changed in
            withObservationTracking {
                _ = secondWindow.connectionRevision
            } onChange: {
                changed()
            }
            firstWindow.connectionDidChange()
        }
        #expect(firstWindow.connectionRevision != originalRevision)
        #expect(secondWindow.connectionRevision == firstWindow.connectionRevision)
        #expect(separateApp.connectionRevision == separateRevision)
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

    @Test func returningToBrowsingDoesNotReplaceTheLoadedConnectionGate() async {
        let credentials = StubCredentials(password: "test-value")
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        await model.loadIfNeeded()
        let loadedState = model.state
        credentials.onRead = {
            Issue.record("Returning to the navigation root must not recheck credentials.")
        }

        await model.loadIfNeeded()

        #expect(credentials.readCount == 1)
        #expect(model.state == loadedState)
    }

    @Test func cancelledInitialConnectionGateCanLoadAgain() async {
        let credentials = StubCredentials(password: "test-value")
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        credentials.error = CancellationError()
        await model.loadIfNeeded()
        #expect(model.state == .idle)

        credentials.error = nil
        await model.loadIfNeeded()
        #expect(model.state == .loaded(ConnectionSummary(serverURL: serverURL, hasCredential: true)))
    }

    #if DEBUG
    @Test func modelNavigationFixtureLoadsWithoutARealServerOrCredentials() async throws {
        let services = ModelNavigationTestServices.make()
        let gate = HomeViewModel(services: services)
        let models = ModelsViewModel(api: services.api)
        await gate.loadIfNeeded()
        await models.fetchPeople()
        let person = try #require(models.people.first)
        #expect(models.people.map(\.id) == [7])
        #expect(models.people.first?.name == "Navigation model")
        let detail = PersonViewModel(id: 7, api: services.api, imageLibrary: services.imageLibrary)
        await detail.detail.loadIfNeeded()
        await detail.albums.loadIfNeeded()
        #expect(detail.detail.state == .loaded(person))
        #expect(detail.albums.state == .empty)
        #expect(gate.state == .loaded(ConnectionSummary(
            serverURL: services.api.baseURL!, hasCredential: true
        )))
    }
    #endif

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

    func request(_ request: APIRequest) async throws -> Data {
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
