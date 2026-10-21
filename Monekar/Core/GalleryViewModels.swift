import Foundation
import Observation

@MainActor
@Observable
final class PaginatedViewModel<Item: Decodable & Identifiable & Equatable & Sendable> where Item.ID: Sendable {
    private(set) var state: LoadState<[Item]> = .idle
    private(set) var items: [Item] = []
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var hasError = false
    private var nextOffset = 0
    private var failedRefresh = true
    private let limit: Int
    private let fetch: (Int, Int) async throws -> MonekarAPI.Page<Item>

    init(limit: Int = 50, fetch: @escaping (Int, Int) async throws -> MonekarAPI.Page<Item>) {
        self.limit = limit
        self.fetch = fetch
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await refresh()
    }

    func refresh() async {
        await load(replacing: true)
    }

    func loadMore() async {
        guard hasMore else { return }
        await load(replacing: false)
    }

    func retry() async {
        guard hasError else { return }
        await load(replacing: failedRefresh)
    }

    private func load(replacing: Bool) async {
        guard !isLoading else { return }
        let previousState = state
        let previousError = hasError
        isLoading = true
        hasError = false
        if items.isEmpty { state = .loading }
        defer { isLoading = false }

        let offset = replacing ? 0 : nextOffset
        do {
            try Task.checkCancellation()
            let page = try await fetch(limit, offset)
            try Task.checkCancellation()
            let (next, overflow) = page.offset.addingReportingOverflow(page.limit)
            guard page.total >= 0, (1...500).contains(page.limit),
                  page.offset == offset, page.items.count <= page.limit, !overflow,
                  !page.items.isEmpty || next >= page.total else {
                throw ConnectionFailure.invalidResponse
            }

            var updated = replacing ? [] : items
            var indices = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })
            for item in page.items {
                if let index = indices[item.id] {
                    updated[index] = item
                } else {
                    indices[item.id] = updated.count
                    updated.append(item)
                }
            }
            items = updated
            total = page.total
            nextOffset = next
            hasMore = next < page.total
            state = items.isEmpty ? .empty : .loaded(items)
        } catch is CancellationError {
            state = previousState
            hasError = previousError
        } catch {
            failedRefresh = replacing
            hasError = true
            // Keep already displayed pages on pagination or refresh failure.
            state = items.isEmpty ? .failed : .loaded(items)
        }
    }
}

@MainActor
@Observable
final class DetailViewModel<Item: Equatable & Sendable> {
    private(set) var state: LoadState<Item> = .idle
    private(set) var isLoading = false
    private(set) var hasError = false
    private let fetch: () async throws -> Item

    init(fetch: @escaping () async throws -> Item) {
        self.fetch = fetch
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        let previousState = state
        let previousError = hasError
        isLoading = true
        hasError = false
        if case .loaded = state {} else { state = .loading }
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let item = try await fetch()
            try Task.checkCancellation()
            state = .loaded(item)
        } catch is CancellationError {
            state = previousState
            hasError = previousError
        } catch {
            hasError = true
            if case .loaded = previousState {
                state = previousState
            } else {
                state = .failed
            }
        }
    }
}

enum PersonSection: String, CaseIterable {
    case albums
    case images
}

@MainActor
@Observable
final class PersonViewModel {
    let detail: DetailViewModel<MonekarAPI.Person>
    let albums: PaginatedViewModel<MonekarAPI.Album>
    let images: PaginatedViewModel<MonekarAPI.Image>
    var selection: PersonSection = .albums

    init(id: Int, api: any APIService) {
        detail = DetailViewModel { try await api.person(id: id) }
        albums = PaginatedViewModel { try await api.albums(personID: id, limit: $0, offset: $1) }
        images = PaginatedViewModel { try await api.images(personID: id, limit: $0, offset: $1) }
    }
}

@MainActor
@Observable
final class AlbumViewModel {
    let detail: DetailViewModel<MonekarAPI.Album>
    let images: PaginatedViewModel<MonekarAPI.Image>

    init(id: Int, api: any APIService) {
        detail = DetailViewModel { try await api.album(id: id) }
        images = PaginatedViewModel { try await api.images(albumID: id, limit: $0, offset: $1) }
    }
}
