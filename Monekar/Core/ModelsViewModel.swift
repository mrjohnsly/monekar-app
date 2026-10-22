import Foundation
import Observation

@MainActor
@Observable
final class ModelsViewModel {
    private let page: PaginatedViewModel<MonekarAPI.Person>

    var people: [MonekarAPI.Person] { page.items }
    var state: LoadState<[MonekarAPI.Person]> { page.state }
    var total: Int { page.total }
    var isLoading: Bool { page.isLoading }
    var hasError: Bool { page.hasError }
    var hasMore: Bool { page.hasMore }

    init(api: any APIService) {
        page = PaginatedViewModel { try await api.people(limit: $0, offset: $1) }
    }

    func fetchPeople() async {
        await page.loadIfNeeded()
    }

    func refresh() async {
        await page.refresh()
    }

    func loadMore() async {
        await page.loadMore()
    }

    func retry() async {
        await page.retry()
    }
}
