import Foundation
import Observation

enum AppRoute: Hashable {
    case connection
    case person(Int)
    case album(Int)
    case favourites
    case tags
    case tag(MonekarAPI.Tag)
}

@MainActor
@Observable
final class AppCoordinator {
    var path: [AppRoute] = []
    let home: HomeViewModel
    let services: AppServices
    private(set) var people: PaginatedViewModel<MonekarAPI.Person>
    private(set) var favourites: PaginatedViewModel<MonekarAPI.Image>
    private(set) var tags: PaginatedViewModel<MonekarAPI.Tag>
    private var tagGalleries: [Int: PaginatedViewModel<MonekarAPI.Image>] = [:]
    private var peopleDetails: [Int: PersonViewModel] = [:]
    private var albumDetails: [Int: AlbumViewModel] = [:]
    private var configuration: ServerConnection?
    private var sessionID: UUID?

    init(services: AppServices) {
        self.services = services
        home = HomeViewModel(services: services)
        people = PaginatedViewModel { try await services.api.people(limit: $0, offset: $1) }
        favourites = services.imageLibrary.feed { try await services.api.favourites(limit: $0, offset: $1) }
        tags = PaginatedViewModel { try await services.api.tags(limit: $0, offset: $1) }
        configuration = services.connectionMetadata.configuration
        sessionID = services.api.mediaSessionID
        services.navigationSession.register(self)
    }

    func person(id: Int) -> PersonViewModel {
        if let model = peopleDetails[id] { return model }
        let model = PersonViewModel(id: id, api: services.api, imageLibrary: services.imageLibrary)
        peopleDetails[id] = model
        return model
    }

    func album(id: Int) -> AlbumViewModel {
        if let model = albumDetails[id] { return model }
        let model = AlbumViewModel(id: id, api: services.api, imageLibrary: services.imageLibrary)
        albumDetails[id] = model
        return model
    }

    func tagImages(id: Int) -> PaginatedViewModel<MonekarAPI.Image> {
        if let model = tagGalleries[id] { return model }
        let model = services.imageLibrary.feed { [services] in
            try await services.api.images(tagID: id, limit: $0, offset: $1)
        }
        tagGalleries[id] = model
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
        services.navigationSession.connectionDidChange()
    }

    fileprivate func synchronizeConnection() {
        let current = services.connectionMetadata.configuration
        guard current != configuration || sessionID != services.api.mediaSessionID else { return }
        configuration = current
        sessionID = services.api.mediaSessionID
        services.imageLibrary.synchronizeConnection()
        people = PaginatedViewModel { [services] in
            try await services.api.people(limit: $0, offset: $1)
        }
        peopleDetails.removeAll()
        albumDetails.removeAll()
        favourites = services.imageLibrary.feed { [services] in
            try await services.api.favourites(limit: $0, offset: $1)
        }
        tags = PaginatedViewModel { [services] in try await services.api.tags(limit: $0, offset: $1) }
        tagGalleries.removeAll()
        path = path.last == .connection ? [.connection] : []
        Task { await home.load() }
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

@MainActor
final class AppNavigationSession {
    private final class Window {
        weak var coordinator: AppCoordinator?

        init(_ coordinator: AppCoordinator) {
            self.coordinator = coordinator
        }
    }

    private var windows: [Window] = []

    func register(_ coordinator: AppCoordinator) {
        windows.removeAll { $0.coordinator == nil }
        windows.append(Window(coordinator))
    }

    func connectionDidChange() {
        windows.removeAll { $0.coordinator == nil }
        for window in windows {
            window.coordinator?.synchronizeConnection()
        }
    }
}
