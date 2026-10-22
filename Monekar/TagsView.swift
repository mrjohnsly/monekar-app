import SwiftUI

struct TagsView: View {
    @Environment(WindowModels.self) private var models
    @Environment(AppServices.self) private var services

    private var viewModel: PaginatedViewModel<MonekarAPI.Tag> { models.browsing.tags }
    private var connectionViewModel: HomeViewModel { models.browsing.tagsConnection }

    var body: some View {
        NavigationStack {
            ConnectedContentView(viewModel: connectionViewModel) {
                tags
            }
            .navigationTitle("Tags")
        }
    }

    private var tags: some View {
        List {
            ForEach(viewModel.items) { tag in
                NavigationLink {
                    TagImagesView(tag: tag)
                } label: {
                    Text(tag.name)
                }
            }
            if viewModel.state == .empty {
                Text("No tags").foregroundStyle(.secondary)
            }
            GalleryFooter(
                count: viewModel.items.count, total: viewModel.total,
                isLoading: viewModel.isLoading || viewModel.state == .idle,
                hasError: viewModel.hasError, hasMore: viewModel.hasMore,
                retry: { await viewModel.retry() },
                loadMore: { await viewModel.loadMore() }
            )
        }
        .task(id: services.imageLibrary.revision) { await viewModel.refreshWhenReady() }
        .refreshable { await viewModel.refresh() }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isLoading)
        }
    }
}

private struct TagImagesView: View {
    let tag: MonekarAPI.Tag
    @Environment(WindowModels.self) private var models

    var body: some View {
        ImageFeedView(title: tag.name, viewModel: models.browsing.images(tagID: tag.id))
    }
}
