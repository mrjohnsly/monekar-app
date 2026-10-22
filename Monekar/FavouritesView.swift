import SwiftUI

struct FavouritesView: View {
    @State private var viewModel: PaginatedViewModel<MonekarAPI.Image>
    let services: AppServices
    let onOpenImage: (ImageViewerSelection) -> Void

    init(services: AppServices, onOpenImage: @escaping (ImageViewerSelection) -> Void) {
        self.services = services
        self.onOpenImage = onOpenImage
        _viewModel = State(initialValue: services.imageLibrary.feed {
            try await services.api.favourites(limit: $0, offset: $1)
        })
    }

    var body: some View {
        NavigationStack {
            ConnectedContentView(services: services) {
                ImageFeedView(
                    title: "Favourites", viewModel: viewModel,
                    services: services, onOpenImage: onOpenImage
                )
            }
            .navigationTitle("Favourites")
        }
    }
}
