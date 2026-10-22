import SwiftUI

struct ModelsView: View {
    @Environment(WindowModels.self) private var windowModels

    private var viewModel: ModelsViewModel { windowModels.browsing.models }
    private var connectionViewModel: HomeViewModel { windowModels.browsing.modelsConnection }

    var body: some View {
        NavigationStack {
            Group {
                switch connectionViewModel.state {
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
                            Task { await connectionViewModel.load() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await connectionViewModel.loadIfNeeded() }
            .navigationTitle("Models")
            .accessibilityIdentifier("homeScreen")
            .navigationDestination(for: Int.self) { personID in
                PersonDetailView(personID: personID)
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
                            ModelCard(person: person)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GalleryThumbnail(
                reference: person.thumbnailURL,
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
