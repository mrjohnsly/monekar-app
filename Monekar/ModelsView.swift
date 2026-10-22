import SwiftUI

struct ModelsView: View {
    @State private var viewModel: ModelsViewModel
    let services: AppServices
    let onOpenImage: (ImageViewerSelection) -> Void

    init(services: AppServices, onOpenImage: @escaping (ImageViewerSelection) -> Void) {
        self.services = services
        self.onOpenImage = onOpenImage
        _viewModel = State(initialValue: ModelsViewModel(api: services.api))
    }

    var body: some View {
        NavigationStack {
            ConnectedContentView(services: services) {
                models
            }
            .navigationTitle("Models")
            .accessibilityIdentifier("homeScreen")
            .navigationDestination(for: Int.self) { personID in
                PersonDetailView(personID: personID, services: services, onOpenImage: onOpenImage)
            }
        }
    }

    private var models: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)],
                    alignment: .leading, spacing: 20
                ) {
                    ForEach(viewModel.people) { person in
                        NavigationLink(value: person.id) {
                            ModelCard(person: person, services: services)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("person-\(person.id)")
                    }
                }
                if viewModel.people.isEmpty && viewModel.state == .empty {
                    GalleryEmptyView(title: "No models", description: "No models are available on this server.")
                }
                GalleryFooter(
                    count: viewModel.people.count, total: viewModel.total,
                    isLoading: viewModel.isLoading || viewModel.state == .idle,
                    hasError: viewModel.hasError, hasMore: viewModel.hasMore,
                    retry: { await viewModel.retry() },
                    loadMore: { await viewModel.loadMore() }
                )
            }
            .padding()
        }
        .navigationTitle("Models")
        .task { await viewModel.fetchPeople() }
        .refreshable { await viewModel.refresh() }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("refreshPeople")
        }
    }
}

private struct ModelCard: View {
    let person: MonekarAPI.Person
    let services: AppServices

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GalleryThumbnail(
                reference: person.thumbnailURL, services: services,
                label: person.name
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(person.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(person.albumCount) albums · \(person.imageCount) images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}
