import Foundation
import Observation

/// Screen state belongs to a window; navigation remains in SwiftUI's stacks.
@MainActor
@Observable
final class WindowModels {
    private let services: AppServices
    @ObservationIgnored private var currentBrowsing: BrowsingModels
    let connection: ConnectionViewModel

    init(services: AppServices) {
        self.services = services
        currentBrowsing = BrowsingModels(services: services)
        connection = ConnectionViewModel(services: services)
    }

    var browsing: BrowsingModels {
        // Resolve the new graph before constructing views with the new stack identity.
        if currentBrowsing.revision != services.connectionRevision {
            currentBrowsing = BrowsingModels(services: services)
        }
        return currentBrowsing
    }
}

@MainActor
final class BrowsingModels {
    let revision: UUID
    let models: ModelsViewModel
    let modelsConnection: HomeViewModel
    let favouritesConnection: HomeViewModel
    let tagsConnection: HomeViewModel
    let favourites: PaginatedViewModel<MonekarAPI.Image>
    let tags: PaginatedViewModel<MonekarAPI.Tag>

    private let services: AppServices
    private var people: [Int: PersonViewModel] = [:]
    private var albums: [Int: AlbumViewModel] = [:]
    private var tagFeeds: [Int: PaginatedViewModel<MonekarAPI.Image>] = [:]

    init(services: AppServices) {
        self.services = services
        revision = services.connectionRevision
        models = ModelsViewModel(api: services.api)
        modelsConnection = HomeViewModel(services: services)
        favouritesConnection = HomeViewModel(services: services)
        tagsConnection = HomeViewModel(services: services)
        favourites = services.imageLibrary.feed {
            try await services.api.favourites(limit: $0, offset: $1)
        }
        tags = PaginatedViewModel {
            try await services.api.tags(limit: $0, offset: $1)
        }
    }

    func person(id: Int) -> PersonViewModel {
        if let model = people[id] { return model }
        let model = PersonViewModel(id: id, api: services.api, imageLibrary: services.imageLibrary)
        people[id] = model
        return model
    }

    func album(id: Int) -> AlbumViewModel {
        if let model = albums[id] { return model }
        let model = AlbumViewModel(id: id, api: services.api, imageLibrary: services.imageLibrary)
        albums[id] = model
        return model
    }

    func images(tagID: Int) -> PaginatedViewModel<MonekarAPI.Image> {
        if let model = tagFeeds[tagID] { return model }
        let model = services.imageLibrary.feed { [services] in
            try await services.api.images(tagID: tagID, limit: $0, offset: $1)
        }
        tagFeeds[tagID] = model
        return model
    }
}
