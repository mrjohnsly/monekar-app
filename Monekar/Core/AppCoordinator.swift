import Observation

enum AppRoute: Hashable {
    case connection
    case person(Int)
    case album(Int)
}

@MainActor
@Observable
final class AppCoordinator {
    var path: [AppRoute] = []
    let home: HomeViewModel
    let services: AppServices
    private(set) var people: PaginatedViewModel<MonekarAPI.Person>
    private var peopleDetails: [Int: PersonViewModel] = [:]
    private var albumDetails: [Int: AlbumViewModel] = [:]
    private var configuration: ServerConnection?

    init(services: AppServices) {
        self.services = services
        home = HomeViewModel(services: services)
        people = PaginatedViewModel { try await services.api.people(limit: $0, offset: $1) }
        configuration = services.connectionMetadata.configuration
    }

    func person(id: Int) -> PersonViewModel {
        if let model = peopleDetails[id] { return model }
        let model = PersonViewModel(id: id, api: services.api)
        peopleDetails[id] = model
        return model
    }

    func album(id: Int) -> AlbumViewModel {
        if let model = albumDetails[id] { return model }
        let model = AlbumViewModel(id: id, api: services.api)
        albumDetails[id] = model
        return model
    }

    func showPerson(id: Int) {
        guard path.last != .person(id) else { return }
        _ = person(id: id)
        path.append(.person(id))
    }

    func showAlbum(id: Int) {
        guard path.last != .album(id) else { return }
        _ = album(id: id)
        path.append(.album(id))
    }

    func connectionDidChange() {
        let current = services.connectionMetadata.configuration
        guard current != configuration else { return }
        configuration = current
        people = PaginatedViewModel { [services] in
            try await services.api.people(limit: $0, offset: $1)
        }
        peopleDetails.removeAll()
        albumDetails.removeAll()
        path = path.last == .connection ? [.connection] : []
    }

    func showConnection() {
        guard path.last != .connection else { return }
        path.append(.connection)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func reset() {
        path.removeAll()
    }
}
