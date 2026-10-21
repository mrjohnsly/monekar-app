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
        let credentials = StubCredentials(token: "test-value")
        let model = HomeViewModel(services: services(url: serverURL, credentials: credentials))
        await model.load()
        #expect(model.state == .loaded(ConnectionSummary(serverURL: serverURL, hasCredential: true)))
    }

    @Test(arguments: [nil, ""])
    func missingCredentialRequiresSignIn(token: String?) async {
        let model = HomeViewModel(services: services(
            url: serverURL, credentials: StubCredentials(token: token)
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
        AppServices(api: StubAPI(baseURL: url), credentials: credentials)
    }
}

private enum StubError: Error {
    case unavailable
}

@MainActor
private struct StubAPI: APIService {
    let baseURL: URL?

    func get(path: [String]) async throws -> Data {
        Data()
    }
}

@MainActor
private final class StubCredentials: CredentialService {
    var token: String?
    var error: (any Error)?
    var onRead: (() async -> Void)?
    var readCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func accessToken() async throws -> String? {
        readCount += 1
        await onRead?()
        if let error { throw error }
        return token
    }

    func setAccessToken(_ token: String?) async throws {
        self.token = token
    }
}
