import Foundation
import Observation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct ModelsViewModelTests {
    @Test func peopleChangesAreObservable() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        await confirmation("People changed") { changed in
            withObservationTracking {
                _ = model.people
            } onChange: {
                changed()
            }
            await model.fetchPeople()
        }
    }

    @Test func fetchPeopleUsesSharedAPIAndLoadsOnlyOnce() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        #expect(model.state == .idle)

        await model.fetchPeople()
        await model.fetchPeople()

        #expect(api.requests.count == 1)
        #expect(api.requests.first?.path == ["api", "v1", "people"])
        #expect(api.requests.first?.queryItems == [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "offset", value: "0")
        ])
        #expect(model.people == [
            .init(id: 7, name: "Server model", albumCount: 12, imageCount: 34, thumbnailURL: "/media/model")
        ])
        #expect(model.state == .loaded(model.people))
        #expect(model.total == 51)
        #expect(model.hasMore)
        #expect(!model.isLoading)
    }

    @Test func loadMoreAndRefreshPreservePaginationBehavior() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        await model.fetchPeople()
        api.response = .success(page(id: 8, total: 51, offset: 50))
        await model.loadMore()
        await model.loadMore()
        #expect(model.people.map(\.id) == [7, 8])
        #expect(!model.hasMore)
        #expect(api.requests.count == 2)
        #expect(api.requests.last?.queryItems.last == URLQueryItem(name: "offset", value: "50"))

        api.response = .success(page(id: 9, total: 1))
        await model.refresh()
        #expect(model.people.map(\.id) == [9])
        #expect(model.total == 1)
        #expect(api.requests.last?.queryItems.last == URLQueryItem(name: "offset", value: "0"))
    }

    @Test func failedPageKeepsPeopleAndRetriesTheSameOffset() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        await model.fetchPeople()
        api.response = .failure(ConnectionFailure.unreachable)
        await model.loadMore()
        #expect(model.people.map(\.id) == [7])
        #expect(model.hasError)
        #expect(!model.isLoading)

        api.response = .success(page(id: 8, total: 51, offset: 50))
        await model.retry()
        #expect(model.people.map(\.id) == [7, 8])
        #expect(!model.hasError)
        #expect(api.requests.suffix(2).allSatisfy {
            $0.queryItems.last == URLQueryItem(name: "offset", value: "50")
        })
    }

    @Test func initialFailureCanRetryAndEmptyLibraryCanRefresh() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        api.response = .failure(ConnectionFailure.unauthorized)
        await model.fetchPeople()
        #expect(model.state == .failed)
        #expect(model.hasError)

        api.response = .success(Data(#"{"items":[],"total":0,"limit":50,"offset":0}"#.utf8))
        await model.retry()
        #expect(model.state == .empty)
        #expect(model.people.isEmpty)
        #expect(!model.hasMore)
        #expect(!model.hasError)

        api.response = .success(page(id: 7, total: 1))
        await model.refresh()
        #expect(model.people.map(\.id) == [7])
    }

    @Test func cancelledFetchCanBeLoadedAgain() async {
        let api = ModelsAPI()
        let model = ModelsViewModel(api: api)
        api.response = .failure(CancellationError())
        await model.fetchPeople()
        #expect(model.state == .idle)
        #expect(!model.hasError)
        #expect(!model.isLoading)

        api.response = .success(page(id: 7, total: 1))
        await model.fetchPeople()
        #expect(model.people.map(\.id) == [7])
    }
}

private func page(id: Int, total: Int, offset: Int = 0) -> Data {
    Data("""
    {"items":[{"id":\(id),"name":"Server model","albumCount":12,"imageCount":34,"thumbnailURL":"/media/model"}],
     "total":\(total),"limit":50,"offset":\(offset)}
    """.utf8)
}

@MainActor
private final class ModelsAPI: APIService {
    var baseURL: URL? = URL(string: "https://example.invalid")
    var requests: [APIRequest] = []
    var response: Result<Data, any Error> = .success(page(id: 7, total: 51))

    func configure(_ configuration: ServerConnection?) { baseURL = configuration?.baseURL }
    func verifyConnection(_ configuration: ServerConnection?) async throws {}
    func get(path: [String]) async throws -> Data { Data() }
    func get(mediaReference: String) async throws -> Data { Data() }

    func request(_ request: APIRequest) async throws -> Data {
        requests.append(request)
        return try response.get()
    }
}
