import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct ImageManagementTests {
    @Test func favouriteUsesIdempotentVerbsAndAuthoritativeImage() async throws {
        let api = ImageManagementAPI()
        let model = ImageViewModel(image: image(), api: api)
        let returned = image(favourite: true, tags: [.init(id: 3, name: "Server")])
        api.respond = { _ in try JSONEncoder().encode(returned) }
        await model.setFavourite(true)
        await model.setFavourite(true)
        #expect(model.image == returned)
        api.respond = { _ in try JSONEncoder().encode(image()) }
        await model.setFavourite(false)
        await model.setFavourite(false)
        #expect(!model.image.isFavourite)
        #expect(api.requests.map(\.method) == [.put, .put, .delete, .delete])
        #expect(api.requests.allSatisfy { $0.path == ["api", "v1", "images", "1", "favourite"] })
        #expect(api.requests.allSatisfy { $0.body == nil })
        #expect(model.errorMessage == nil)
    }

    @Test func normalizedTagsReplaceAssignmentsWithoutDuplicates() async throws {
        let api = ImageManagementAPI()
        let library = ImageLibrary(api: api)
        let model = library.model(for: image())
        api.respond = { _ in try JSONEncoder().encode(MonekarAPI.Tag(id: 9, name: "summer holiday")) }
        model.tagName = "  Summer   Holiday  "
        await model.addTag()
        #expect(model.image.tags == [.init(id: 9, name: "summer holiday")])
        #expect(model.tagName.isEmpty)
        #expect(library.revision == 1)
        let request = try #require(api.requests.first)
        #expect(request.method == .post)
        #expect(request.path == ["api", "v1", "images", "1", "tags"])
        #expect(try JSONDecoder().decode([String: String].self, from: #require(request.body)) ==
                ["name": "  Summer   Holiday  "])
        model.tagName = "SUMMER HOLIDAY"
        await model.addTag()
        #expect(model.image.tags.count == 1)
        api.respond = { _ in Data() }
        await model.removeTag(id: 9)
        #expect(model.image.tags.isEmpty)
        #expect(api.requests.last?.method == .delete)
        #expect(api.requests.last?.path == ["api", "v1", "images", "1", "tags", "9"])
        #expect(library.revision == 3)
    }

    @Test(arguments: ["", " ", "\n\t"])
    func emptyTagInputDoesNotMakeRequests(name: String) async {
        let api = ImageManagementAPI()
        let model = ImageViewModel(image: image(), api: api)
        model.tagName = name
        await model.addTag()
        #expect(api.requests.isEmpty)
        #expect(model.image.tags.isEmpty)
        #expect(model.tagName == name)
        #expect(model.errorMessage == "Enter a tag name.")
    }

    @Test(arguments: [
        ConnectionFailure.unauthorized, .unreachable, .serverRejected(400),
        .serverRejected(404), .serverRejected(422), .decodingFailed
    ])
    func failedMutationsPreserveImageAndInput(failure: ConnectionFailure) async {
        let api = ImageManagementAPI()
        api.respond = { _ in throw failure }
        let library = ImageLibrary(api: api)
        let original = image(tags: [.init(id: 9, name: "Existing")])
        let model = library.model(for: original)
        model.tagName = "New"
        await model.setFavourite(true)
        #expect(model.image == original)
        #expect(model.errorMessage != nil)
        await model.addTag()
        #expect(model.image == original)
        #expect(model.tagName == "New")
        #expect(model.errorMessage != nil)
        await model.removeTag(id: 9)
        #expect(model.image == original)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
        #expect(library.revision == 0)
        if failure == .serverRejected(404) {
            #expect(model.errorMessage == "This image is no longer available.")
        }
        api.respond = { _ in try JSONEncoder().encode(image(favourite: true)) }
        await model.setFavourite(true)
        #expect(model.image.isFavourite)
        #expect(model.errorMessage == nil)
    }

    @Test func tagsLoadFromServerAndFailedReloadRetainsAssignments() async {
        let api = ImageManagementAPI()
        let model = ImageViewModel(image: image(), api: api)
        api.respond = { _ in try JSONEncoder().encode([MonekarAPI.Tag(id: 8, name: "Normalized")]) }
        await model.loadTags()
        #expect(model.image.tags == [.init(id: 8, name: "Normalized")])
        #expect(api.requests.first?.method == .get)
        #expect(api.requests.first?.path == ["api", "v1", "images", "1", "tags"])
        api.respond = { _ in throw ConnectionFailure.unauthorized }
        await model.loadTags()
        #expect(model.image.tags == [.init(id: 8, name: "Normalized")])
        #expect(model.errorMessage == ConnectionFailure.unauthorized.message)
    }

    @Test func pendingMutationDoesNotChangeStateOrAllowOverlappingActions() async throws {
        let api = ImageManagementAPI()
        var continuation: CheckedContinuation<Data, Never>?
        api.respond = { _ in await withCheckedContinuation { continuation = $0 } }
        let model = ImageViewModel(image: image(), api: api)
        let task = Task { await model.setFavourite(true) }
        while continuation == nil { await Task.yield() }
        #expect(model.isBusy)
        #expect(!model.image.isFavourite)
        await model.setFavourite(false)
        model.tagName = "New"
        await model.addTag()
        await model.removeTag(id: 9)
        await model.loadTags()
        #expect(api.requests.count == 1)
        continuation?.resume(returning: try JSONEncoder().encode(image(favourite: true)))
        await task.value
        #expect(model.image.isFavourite)
        #expect(!model.isBusy)
    }

    @Test func sharedModelsReceiveFreshPagesButIgnoreReadsOlderThanMutations() async throws {
        let api = ImageManagementAPI()
        let library = ImageLibrary(api: api)
        let model = library.model(for: image())
        #expect(library.model(for: image()) === model)
        let feed = library.feed { limit, offset in
            .init(items: [image(tags: [.init(id: 2, name: "Fresh")])], total: 1, limit: limit, offset: offset)
        }
        await feed.refresh()
        #expect(model.image.tags == [.init(id: 2, name: "Fresh")])

        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Image>, Never>?
        let staleFeed = library.feed { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await staleFeed.refresh() }
        while continuation == nil { await Task.yield() }
        api.respond = { _ in try JSONEncoder().encode(image(favourite: true)) }
        await model.setFavourite(true)
        continuation?.resume(returning: .init(items: [image()], total: 1, limit: 50, offset: 0))
        await task.value
        #expect(library.model(for: try #require(staleFeed.items.first)).image.isFavourite)
    }

    @Test func connectionChangeDiscardsOldModelsAndLateResponses() async throws {
        let api = ImageManagementAPI()
        let library = ImageLibrary(api: api)
        let oldModel = library.model(for: image())
        var continuation: CheckedContinuation<Data, Never>?
        api.respond = { _ in await withCheckedContinuation { continuation = $0 } }
        let task = Task { await oldModel.setFavourite(true) }
        while continuation == nil { await Task.yield() }
        api.configure(nil)
        let newModel = library.model(for: image())
        #expect(newModel !== oldModel)
        let version = library.revision
        continuation?.resume(returning: try JSONEncoder().encode(image(favourite: true)))
        await task.value
        #expect(!oldModel.image.isFavourite)
        #expect(!newModel.image.isFavourite)
        #expect(library.revision == version)
        await oldModel.removeTag(id: 9)
        #expect(api.requests.count == 1)
    }

    @Test func mutationsDoNotDiscardFreshReadsForUnrelatedImages() async {
        let api = ImageManagementAPI()
        let library = ImageLibrary(api: api)
        let first = library.model(for: image(id: 1))
        let second = library.model(for: image(id: 2))
        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Image>, Never>?
        let feed = library.feed { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await feed.refresh() }
        while continuation == nil { await Task.yield() }
        api.respond = { _ in try JSONEncoder().encode(image(id: 2, favourite: true)) }
        await second.setFavourite(true)
        continuation?.resume(returning: .init(
            items: [image(id: 1, favourite: true), image(id: 2)],
            total: 2, limit: 50, offset: 0
        ))
        await task.value
        #expect(first.image.isFavourite)
        #expect(second.image.isFavourite)
    }

    @Test(arguments: [false, true])
    func modelsCreatedDuringFetchReceiveFreshDataUnlessMutated(mutate: Bool) async {
        let api = ImageManagementAPI()
        let library = ImageLibrary(api: api)
        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Image>, Never>?
        let feed = library.feed { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }
        let task = Task { await feed.refresh() }
        while continuation == nil { await Task.yield() }
        let model = library.model(for: image())
        if mutate {
            api.respond = { _ in try JSONEncoder().encode(image(tags: [.init(id: 3, name: "New")])) }
            await model.setFavourite(false)
        }
        continuation?.resume(returning: .init(
            items: [image(favourite: true)], total: 1, limit: 50, offset: 0
        ))
        await task.value
        #expect(model.image.isFavourite == !mutate)
        #expect(model.image.tags.isEmpty == !mutate)
    }

    @Test func wrongImageResponseIsRejected() async {
        let api = ImageManagementAPI()
        let model = ImageViewModel(image: image(), api: api)
        api.respond = { _ in try JSONEncoder().encode(image(id: 99, favourite: true)) }
        await model.setFavourite(true)
        #expect(model.image == image())
        #expect(model.errorMessage == ConnectionFailure.invalidResponse.message)
    }

    @Test func mutationTriggeredRefreshWaitsForCancelledFeedRead() async {
        var continuation: CheckedContinuation<MonekarAPI.Page<MonekarAPI.Image>, Never>?
        var requests = 0
        let feed = PaginatedViewModel<MonekarAPI.Image> { limit, offset in
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return .init(items: [image(favourite: true)], total: 1, limit: limit, offset: offset)
        }
        let initial = Task { await feed.refreshWhenReady() }
        while continuation == nil { await Task.yield() }
        initial.cancel()
        let refresh = Task { await feed.refreshWhenReady() }
        await Task.yield()
        continuation?.resume(returning: .init(items: [image()], total: 1, limit: 50, offset: 0))
        await initial.value
        await refresh.value
        #expect(requests == 2)
        #expect(feed.items.first?.isFavourite == true)
    }

    @Test func favouritesAndTagGalleriesPageAndRecoverFromFailures() async throws {
        let api = ImageManagementAPI()
        let metadata = UserDefaultsConnectionMetadataService(
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        let services = AppServices(api: api, credentials: ImageManagementCredentials(), connectionMetadata: metadata)
        let coordinator = AppCoordinator(services: services)
        api.respond = { request in
            let offset = request.queryItems.first { $0.name == "offset" }?.value ?? "0"
            let items = request.path == ["api", "v1", "tags"]
                ? try JSONEncoder().encode([MonekarAPI.Tag(id: 9, name: "Server tag")])
                : try JSONEncoder().encode([image(id: offset == "0" ? 1 : 2, favourite: true)])
            return Data(#"{"items":"#.utf8) + items +
                Data(#","total":51,"limit":50,"offset":\#(offset)}"#.utf8)
        }
        await coordinator.favourites.loadIfNeeded()
        await coordinator.favourites.loadMore()
        #expect(coordinator.favourites.items.map(\.id) == [1, 2])
        #expect(!coordinator.favourites.hasMore)
        await coordinator.tags.loadIfNeeded()
        await coordinator.tags.loadMore()
        let gallery = coordinator.tagImages(id: 9)
        await gallery.loadIfNeeded()
        await gallery.loadMore()
        #expect(gallery.items.map(\.id) == [1, 2])
        #expect(coordinator.tagImages(id: 9) === gallery)
        #expect(api.requests.map(\.path) == [
            ["api", "v1", "favourites"], ["api", "v1", "favourites"],
            ["api", "v1", "tags"], ["api", "v1", "tags"],
            ["api", "v1", "tags", "9", "images"], ["api", "v1", "tags", "9", "images"]
        ])
        #expect(api.requests.map { $0.queryItems.last?.value } == ["0", "50", "0", "50", "0", "50"])
        api.respond = { _ in throw ConnectionFailure.unauthorized }
        await coordinator.favourites.refresh()
        await gallery.refresh()
        await coordinator.tags.refresh()
        #expect(coordinator.favourites.hasError)
        #expect(coordinator.favourites.items.count == 2)
        #expect(gallery.hasError)
        #expect(gallery.items.count == 2)
        #expect(coordinator.tags.hasError)
        let oldFavourites = coordinator.favourites
        let oldTags = coordinator.tags
        api.configure(nil)
        coordinator.connectionDidChange()
        #expect(coordinator.favourites !== oldFavourites)
        #expect(coordinator.tags !== oldTags)
        #expect(coordinator.tagImages(id: 9) !== gallery)
        #expect(coordinator.favourites.items.isEmpty)
    }
}

private func image(id: Int = 1, favourite: Bool = false, tags: [MonekarAPI.Tag] = []) -> MonekarAPI.Image {
    .init(
        id: id, albumID: 2, fileName: "image.jpg", format: "jpeg", byteSize: 100,
        width: nil, height: nil, thumbnailURL: "/thumbnail", originalURL: "/original",
        isFavourite: favourite, tags: tags
    )
}

@MainActor
private final class ImageManagementAPI: APIService {
    var baseURL: URL? = URL(string: "https://example.invalid")
    var mediaSessionID: UUID? = UUID()
    var requests: [APIRequest] = []
    var respond: (APIRequest) async throws -> Data = { _ in throw ConnectionFailure.invalidResponse }
    func configure(_ configuration: ServerConnection?) { mediaSessionID = UUID() }
    func verifyConnection(_ configuration: ServerConnection?) async throws {}
    func get(path: [String]) async throws -> Data { Data() }
    func get(mediaReference: String) async throws -> Data { Data() }
    func request(_ request: APIRequest) async throws -> Data {
        requests.append(request)
        return try await respond(request)
    }
}

@MainActor
private final class ImageManagementCredentials: CredentialService {
    func password() async throws -> String? { nil }
    func setPassword(_ password: String?) async throws {}
}
