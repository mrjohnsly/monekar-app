import SwiftUI

struct ModelsView: View {
    @State private var viewModel: ModelsViewModel
    let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: coordinator.people)
    }

    var body: some View {
        Group {
            switch coordinator.home.state {
            case .idle, .loading:
                ProgressView("Loading connection…")
            case .empty:
                ContentUnavailableView(
                    "No server configured",
                    systemImage: "network",
                    description: Text("Open Settings to set up a server connection.")
                )
            case .loaded(let summary):
                if summary.hasCredential {
                    models
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.largeTitle)
                        Text("Sign-in required")
                            .font(.title)
                        Text(summary.serverURL.host() ?? "monekar-server")
                        Text("Open Settings, then Connection to sign in again.")
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed:
                ContentUnavailableView {
                    Label("Unable to load connection", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your configuration and try again.")
                } actions: {
                    Button("Retry") {
                        Task { await coordinator.home.load() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Models")
        .accessibilityIdentifier("homeScreen")
        .task { await coordinator.home.load() }
    }

    private var models: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)],
                    alignment: .leading, spacing: 20
                ) {
                    ForEach(viewModel.people) { person in
                        ModelCard(person: person, services: coordinator.services) {
                            coordinator.showPerson(id: person.id)
                        }
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
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GalleryThumbnail(
                reference: person.thumbnailURL, services: services,
                label: person.name, open: open
            )
            Button(action: open) {
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
            .buttonStyle(.plain)
            .accessibilityIdentifier("person-\(person.id)")
        }
    }
}
