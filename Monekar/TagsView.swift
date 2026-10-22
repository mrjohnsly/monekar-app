import SwiftUI

struct TagsView: View {
    @State private var viewModel: PaginatedViewModel<MonekarAPI.Tag>
    let services: AppServices
    let onOpenImage: (ImageViewerSelection) -> Void

    init(services: AppServices, onOpenImage: @escaping (ImageViewerSelection) -> Void) {
        self.services = services
        self.onOpenImage = onOpenImage
        _viewModel = State(initialValue: PaginatedViewModel {
            try await services.api.tags(limit: $0, offset: $1)
        })
    }

    var body: some View {
        NavigationStack {
            ConnectedContentView(services: services) {
                tags
            }
            .navigationTitle("Tags")
        }
    }

    private var tags: some View {
        List {
            ForEach(viewModel.items) { tag in
                NavigationLink {
                    TagImagesView(tag: tag, services: services, onOpenImage: onOpenImage)
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
    @State private var viewModel: PaginatedViewModel<MonekarAPI.Image>
    let tag: MonekarAPI.Tag
    let services: AppServices
    let onOpenImage: (ImageViewerSelection) -> Void

    init(tag: MonekarAPI.Tag, services: AppServices, onOpenImage: @escaping (ImageViewerSelection) -> Void) {
        self.tag = tag
        self.services = services
        self.onOpenImage = onOpenImage
        _viewModel = State(initialValue: services.imageLibrary.feed {
            try await services.api.images(tagID: tag.id, limit: $0, offset: $1)
        })
    }

    var body: some View {
        ImageFeedView(title: tag.name, viewModel: viewModel, services: services, onOpenImage: onOpenImage)
    }
}
