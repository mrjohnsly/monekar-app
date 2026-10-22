import SwiftUI

struct FavouritesView: View {
    @Environment(WindowModels.self) private var models

    private var viewModel: PaginatedViewModel<MonekarAPI.Image> { models.browsing.favourites }
    private var connectionViewModel: HomeViewModel { models.browsing.favouritesConnection }

    var body: some View {
        NavigationStack {
            ConnectedContentView(viewModel: connectionViewModel) {
                ImageFeedView(title: "Favourites", viewModel: viewModel)
            }
            .navigationTitle("Favourites")
        }
    }
}
