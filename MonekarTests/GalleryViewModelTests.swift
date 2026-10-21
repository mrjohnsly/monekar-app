import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct GalleryViewModelTests {
    @Test func pagesLoadOnDemandAndStopAtServerTotal() async {
        var offsets: [Int] = []
        let model = PaginatedViewModel<MonekarAPI.Person>(limit: 2) { limit, offset in
            offsets.append(offset)
            return .init(items: [person(offset + 1)], total: 3, limit: limit, offset: offset)
        }
        #expect(model.state == .idle)
        await model.loadIfNeeded()
        #expect(model.items.map(\.id) == [1])
        #expect(model.total == 3)
        #expect(model.hasMore)
        await model.loadIfNeeded()
        #expect(offsets == [0])
        await model.loadMore()
        await model.loadMore()
        #expect(offsets == [0, 2])
        #expect(model.items.map(\.id) == [1, 3])
        #expect(!model.hasMore)
    }

    @Test func emptyLibraryCanBeRefreshed() async {
        var empty = true
        let model = PaginatedViewModel<MonekarAPI.Person> { limit, offset in
            .init(items: empty ? [] : [person(1)], total: empty ? 0 : 1, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        #expect(model.state == .empty)
        #expect(!model.hasMore)
        empty = false
        await model.refresh()
        #expect(model.state == .loaded([person(1)]))
    }

    @Test func initialFailureRetriesFirstPage() async {
        var fail = true
        var offsets: [Int] = []
        let model = PaginatedViewModel<MonekarAPI.Person> { limit, offset in
            offsets.append(offset)
            if fail { throw ConnectionFailure.unauthorized }
            return .init(items: [person(1)], total: 1, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        #expect(model.state == .failed)
        #expect(model.hasError)
        fail = false
        await model.retry()
        #expect(offsets == [0, 0])
        #expect(model.items == [person(1)])
        #expect(!model.hasError)
    }

    @Test func pageFailureKeepsItemsAndRetriesSameOffset() async {
        var fail = true
        var offsets: [Int] = []
        let model = PaginatedViewModel<MonekarAPI.Person>(limit: 1) { limit, offset in
            offsets.append(offset)
            if offset == 1 && fail { throw ConnectionFailure.unreachable }
            return .init(items: [person(offset + 1)], total: 2, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        await model.loadMore()
        #expect(model.state == .loaded([person(1)]))
        #expect(model.hasError)
        #expect(model.hasMore)
        fail = false
        await model.retry()
        #expect(offsets == [0, 1, 1])
        #expect(model.items.map(\.id) == [1, 2])
    }

    @Test func refreshFailureRetainsItemsAndRetriesReplacement() async {
        var fail = false
        var version = 1
        var offsets: [Int] = []
        let model = PaginatedViewModel<MonekarAPI.Person>(limit: 1) { limit, offset in
            offsets.append(offset)
            if fail { throw ConnectionFailure.unreachable }
            return .init(items: [person(version + offset)], total: 2, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        await model.loadMore()
        fail = true
        await model.refresh()
        #expect(model.items.map(\.id) == [1, 2])
        #expect(model.hasError)
        fail = false
        version = 10
        await model.retry()
        #expect(offsets == [0, 1, 0, 0])
        #expect(model.items.map(\.id) == [10])
        #expect(model.hasMore)
    }

    @Test func overlappingIDsUpdateWithoutDuplicateRows() async {
        let model = PaginatedViewModel<MonekarAPI.Person>(limit: 2) { limit, offset in
            .init(items: offset == 0 ? [person(1), person(2)] : [person(2, name: "Updated"), person(3)],
                  total: 4, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        await model.loadMore()
        #expect(model.items.map(\.id) == [1, 2, 3])
        #expect(model.items[1].name == "Updated")
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func malformedPagesFailSafely(kind: Int) async {
        let model = PaginatedViewModel<MonekarAPI.Person> { _, _ in
            switch kind {
            case 0: .init(items: [], total: -1, limit: 1, offset: 0)
            case 1: .init(items: [], total: 0, limit: 0, offset: 0)
            case 2: .init(items: [], total: 0, limit: 501, offset: 0)
            case 3: .init(items: [], total: 0, limit: 1, offset: 1)
            case 4: .init(items: [person(1), person(2)], total: 2, limit: 1, offset: 0)
            default: .init(items: [], total: 100, limit: 50, offset: 0)
            }
        }
        await model.loadIfNeeded()
        #expect(model.state == .failed)
        #expect(model.items.isEmpty)
        #expect(model.hasError)
    }

    @Test func cancellationRestoresStateAndAllowsReload() async {
        var cancel = true
        let model = PaginatedViewModel<MonekarAPI.Person> { limit, offset in
            if cancel { throw CancellationError() }
            return .init(items: [person(1)], total: 1, limit: limit, offset: offset)
        }
        await model.loadIfNeeded()
        #expect(model.state == .idle)
        #expect(!model.isLoading)
        #expect(!model.hasError)
        cancel = false
        await model.loadIfNeeded()
        cancel = true
        await model.refresh()
        #expect(model.state == .loaded([person(1)]))
    }

    @Test func duplicateLoadsAreIgnoredWhileRequestIsSuspended() async {
        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Person>, Never>?
        var requests = 0
        let model = PaginatedViewModel<MonekarAPI.Person> { _, _ in
            requests += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await model.loadIfNeeded() }
        while continuation == nil { await Task.yield() }
        #expect(model.state == .loading)
        #expect(model.isLoading)
        let duplicate = Task { await model.loadIfNeeded() }
        await Task.yield()
        await model.refresh()
        await model.loadMore()
        #expect(requests == 1)
        duplicate.cancel()
        task.cancel()
        continuation?.resume(returning: .init(items: [person(1)], total: 1, limit: 50, offset: 0))
        await task.value
        await duplicate.value
        #expect(model.state == .idle)
        #expect(model.items.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func detailFailureRetryRefreshAndCancellation() async {
        var failure: (any Error)? = ConnectionFailure.unreachable
        var name = "First"
        var requests = 0
        let model = DetailViewModel {
            requests += 1
            if let failure { throw failure }
            return person(1, name: name)
        }
        await model.loadIfNeeded()
        #expect(model.state == .failed)
        #expect(model.hasError)
        failure = nil
        await model.refresh()
        await model.loadIfNeeded()
        #expect(requests == 2)
        #expect(model.state == .loaded(person(1, name: "First")))
        failure = ConnectionFailure.unreachable
        await model.refresh()
        #expect(model.hasError)
        #expect(model.state == .loaded(person(1, name: "First")))
        failure = CancellationError()
        await model.refresh()
        #expect(model.hasError)
        #expect(!model.isLoading)
        failure = nil
        name = "Updated"
        await model.refresh()
        #expect(model.state == .loaded(person(1, name: "Updated")))
        #expect(!model.hasError)
    }

    @Test func detailLoadingIgnoresDuplicateRequestsAndDiscardsCancelledResponse() async {
        var continuation: CheckedContinuation<MonekarAPI.Person, Never>?
        var requests = 0
        let model = DetailViewModel {
            requests += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await model.loadIfNeeded() }
        while continuation == nil { await Task.yield() }
        #expect(model.state == .loading)
        #expect(model.isLoading)
        await model.refresh()
        #expect(requests == 1)
        task.cancel()
        continuation?.resume(returning: person(1))
        await task.value
        #expect(model.state == .idle)
        #expect(!model.isLoading)
        #expect(!model.hasError)
    }

    @Test func reopeningPageWhileCancelledRequestUnwindsRestartsLoading() async {
        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Person>, Never>?
        var requests = 0
        let model = PaginatedViewModel<MonekarAPI.Person> { limit, offset in
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return .init(items: [person(2)], total: 1, limit: limit, offset: offset)
        }
        let original = Task { await model.loadIfNeeded() }
        while continuation == nil { await Task.yield() }
        original.cancel()
        let reopened = Task { await model.loadIfNeeded() }
        await Task.yield()
        continuation?.resume(returning: .init(items: [person(1)], total: 1, limit: 50, offset: 0))
        await original.value
        await reopened.value
        #expect(requests == 2)
        #expect(model.state == .loaded([person(2)]))
    }

    @Test func reopeningDetailWhileCancelledRequestUnwindsRestartsLoading() async {
        var continuation: CheckedContinuation<MonekarAPI.Person, Never>?
        var requests = 0
        let model = DetailViewModel {
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return person(2)
        }
        let original = Task { await model.loadIfNeeded() }
        while continuation == nil { await Task.yield() }
        original.cancel()
        let reopened = Task { await model.loadIfNeeded() }
        await Task.yield()
        continuation?.resume(returning: person(1))
        await original.value
        await reopened.value
        #expect(requests == 2)
        #expect(model.state == .loaded(person(2)))
    }

    @Test func browsingModelsUseTypedEndpointsAndServerFields() async throws {
        let api = GalleryAPI()
        let personModel = PersonViewModel(id: 7, api: api)
        await personModel.detail.loadIfNeeded()
        await personModel.albums.loadIfNeeded()
        await personModel.images.loadIfNeeded()
        let albumModel = AlbumViewModel(id: 9, api: api)
        await albumModel.detail.loadIfNeeded()
        await albumModel.images.loadIfNeeded()
        #expect(api.requests.map(\.path) == [
            ["api", "v1", "people", "7"],
            ["api", "v1", "people", "7", "albums"],
            ["api", "v1", "people", "7", "images"],
            ["api", "v1", "albums", "9"],
            ["api", "v1", "albums", "9", "images"]
        ])
        for request in api.requests where request.path.count == 5 {
            #expect(request.queryItems == [
                URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: "0")
            ])
        }
        #expect(personModel.detail.state == .loaded(person(7)))
        #expect(personModel.albums.items.first?.name == "Server album")
        #expect(personModel.albums.items.first?.imageCount == 23)
        #expect(personModel.images.items.first?.thumbnailURL == "/media/image-thumb")
        #expect(albumModel.images.total == 1)
        #expect(albumModel.detail.state == .loaded(GalleryAPI.album))
    }

    @Test func coordinatorPreservesScreenModelsAndSelectionsAcrossNavigation() async {
        let (services, _) = galleryServices()
        let coordinator = AppCoordinator(services: services)
        await coordinator.people.loadIfNeeded()
        #expect(coordinator.people.items == [person(7)])
        coordinator.showPerson(id: 7)
        coordinator.showPerson(id: 7)
        let personModel = coordinator.person(id: 7)
        await personModel.images.loadIfNeeded()
        personModel.selection = .images
        coordinator.showAlbum(id: 9)
        coordinator.showAlbum(id: 9)
        let albumModel = coordinator.album(id: 9)
        await albumModel.images.loadIfNeeded()
        #expect(coordinator.path == [.person(7), .album(9)])
        coordinator.showConnection()
        coordinator.connectionDidChange()
        coordinator.pop()
        #expect(coordinator.path == [.person(7), .album(9)])
        coordinator.pop()
        #expect(coordinator.person(id: 7) === personModel)
        #expect(coordinator.person(id: 7).selection == .images)
        #expect(coordinator.person(id: 7).images.items.count == 1)
        coordinator.showAlbum(id: 9)
        #expect(coordinator.album(id: 9) === albumModel)
        coordinator.reset()
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.people.items == [person(7)])
    }

    @Test func windowsHaveIndependentGalleryState() {
        let (services, _) = galleryServices()
        let first = AppCoordinator(services: services)
        let second = AppCoordinator(services: services)
        first.showPerson(id: 7)
        first.person(id: 7).selection = .images
        #expect(second.path.isEmpty)
        #expect(second.person(id: 7).selection == .albums)
        #expect(first.people !== second.people)
    }

    @Test func connectionChangesDiscardPreviousServerGallery() async throws {
        let (services, metadata) = galleryServices()
        let coordinator = AppCoordinator(services: services)
        let oldPeople = coordinator.people
        let oldPerson = coordinator.person(id: 7)
        let oldAlbum = coordinator.album(id: 9)
        coordinator.showPerson(id: 7)
        coordinator.showAlbum(id: 9)
        coordinator.showConnection()
        try metadata.save(ServerConnection(serverURL: "https://other.invalid", username: "other"))
        coordinator.connectionDidChange()
        #expect(coordinator.path == [.connection])
        coordinator.pop()
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.people !== oldPeople)
        #expect(coordinator.people.state == .idle)
        #expect(coordinator.person(id: 7) !== oldPerson)
        #expect(coordinator.album(id: 9) !== oldAlbum)
        coordinator.showPerson(id: 7)
        try metadata.remove()
        coordinator.connectionDidChange()
        #expect(coordinator.path.isEmpty)
    }

    @Test func connectionChangesInvalidateEveryWindowSharingTheAPI() async throws {
        let (services, metadata) = galleryServices()
        let first = AppCoordinator(services: services)
        let second = AppCoordinator(services: services)
        await second.people.loadIfNeeded()
        let oldPeople = second.people
        let oldPerson = second.person(id: 7)
        second.showPerson(id: 7)
        second.showAlbum(id: 9)
        first.showConnection()
        try metadata.save(ServerConnection(serverURL: "https://other.invalid", username: "other"))
        services.api.configure(metadata.configuration)
        first.connectionDidChange()
        #expect(first.path == [.connection])
        #expect(second.path.isEmpty)
        #expect(second.people !== oldPeople)
        #expect(second.people.state == .idle)
        #expect(second.person(id: 7) !== oldPerson)
        #expect(second.person(id: 7).selection == .albums)
        let newPeople = second.people
        first.connectionDidChange()
        #expect(second.people === newPeople)
        second.showPerson(id: 7)
        try metadata.remove()
        services.api.configure(nil)
        first.connectionDidChange()
        #expect(second.path.isEmpty)
        #expect(second.people !== newPeople)
    }
}

private func person(_ id: Int, name: String = "Server person") -> MonekarAPI.Person {
    .init(id: id, name: name, albumCount: 12, imageCount: 34, thumbnailURL: "/media/person-thumb")
}

@MainActor
private func galleryServices() -> (AppServices, GalleryMetadata) {
    let metadata = GalleryMetadata()
    return (AppServices(api: GalleryAPI(), credentials: GalleryCredentials(), connectionMetadata: metadata), metadata)
}

@MainActor
private final class GalleryAPI: APIService {
    var baseURL: URL? = URL(string: "https://example.invalid")
    var requests: [APIRequest] = []
    static let album = MonekarAPI.Album(
        id: 9, personID: 7, name: "Server album", date: "2026-10-01", models: ["Server models"],
        photographer: "Server photographer", imageCount: 23, thumbnailURL: "/media/album-thumb"
    )
    private let image = MonekarAPI.Image(
        id: 11, albumID: 9, fileName: "photo.jpg", format: "jpeg", byteSize: 2048,
        width: 640, height: 480, thumbnailURL: "/media/image-thumb", originalURL: "/media/original",
        isFavourite: false, tags: []
    )

    func configure(_ configuration: ServerConnection?) { baseURL = configuration?.baseURL }
    func verifyConnection(_ configuration: ServerConnection?) async throws {}
    func get(path: [String]) async throws -> Data { Data() }
    func get(mediaReference: String) async throws -> Data { Data() }

    func request(_ request: APIRequest) async throws -> Data {
        requests.append(request)
        let encoder = JSONEncoder()
        switch request.path {
        case ["api", "v1", "people"]:
            return Data(#"{"items":[{"id":7,"name":"Server person","albumCount":12,"imageCount":34,"thumbnailURL":"/media/person-thumb"}],"total":1,"limit":50,"offset":0}"#.utf8)
        case ["api", "v1", "people", "7"]:
            return try encoder.encode(MonekarAPI.Person(
                id: 7, name: "Server person", albumCount: 12, imageCount: 34,
                thumbnailURL: "/media/person-thumb"
            ))
        case ["api", "v1", "albums", "9"]:
            return try encoder.encode(Self.album)
        case ["api", "v1", "people", "7", "albums"]:
            return try pageData(encoder.encode([Self.album]))
        case ["api", "v1", "people", "7", "images"], ["api", "v1", "albums", "9", "images"]:
            return try pageData(encoder.encode([image]))
        default:
            throw ConnectionFailure.invalidURL
        }
    }

    private func pageData(_ items: Data) -> Data {
        Data(#"{"items":"#.utf8) + items + Data(#","total":1,"limit":50,"offset":0}"#.utf8)
    }
}

@MainActor
private final class GalleryCredentials: CredentialService {
    func password() async throws -> String? { nil }
    func setPassword(_ password: String?) async throws {}
}

@MainActor
private final class GalleryMetadata: ConnectionMetadataService {
    var configuration: ServerConnection?
    func save(_ configuration: ServerConnection) throws { self.configuration = configuration }
    func remove() throws { configuration = nil }
}
