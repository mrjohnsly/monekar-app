import SwiftUI

struct AppNavigationView<Content: View>: View {
    @State private var coordinator: AppCoordinator
    let title: String
    let requiresConnection: Bool
    let onOpenImage: (ImageViewerSelection) -> Void
    let content: (AppCoordinator) -> Content

    init(
        _ title: String,
        services: AppServices,
        requiresConnection: Bool = true,
        onOpenImage: @escaping (ImageViewerSelection) -> Void,
        @ViewBuilder content: @escaping (AppCoordinator) -> Content
    ) {
        _coordinator = State(initialValue: AppCoordinator(services: services))
        self.title = title
        self.requiresConnection = requiresConnection
        self.onOpenImage = onOpenImage
        self.content = content
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.path) {
            Group {
                if requiresConnection {
                    ConnectedContentView(viewModel: coordinator.home) {
                        content(coordinator)
                    }
                } else {
                    content(coordinator)
                }
            }
                .navigationTitle(title)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .libraryScan:
                        LibraryScanView(viewModel: coordinator.services.libraryScan)
                    case .person(let id):
                        PersonDetailView(
                            viewModel: coordinator.person(id: id),
                            coordinator: coordinator,
                            onOpenImage: onOpenImage
                        )
                    case .album(let id):
                        AlbumDetailView(
                            viewModel: coordinator.album(id: id),
                            services: coordinator.services,
                            onOpenImage: onOpenImage
                        )
                    case .favourites:
                        ImageFeedView(
                            title: "Favourites", viewModel: coordinator.favourites,
                            services: coordinator.services,
                            onOpenImage: onOpenImage
                        )
                    case .tags:
                        TagsView(coordinator: coordinator)
                    case .tag(let tag):
                        ImageFeedView(
                            title: tag.name, viewModel: coordinator.tagImages(id: tag.id),
                            services: coordinator.services,
                            onOpenImage: onOpenImage
                        )
                    case .connection:
                        ConnectionView(
                            services: coordinator.services,
                            onConnectionChanged: { coordinator.connectionDidChange() }
                        ) {
                            Task {
                                await coordinator.home.load()
                                coordinator.connectionDidChange()
                                coordinator.pop()
                            }
                        }
                        .onDisappear {
                            coordinator.connectionDidChange()
                            Task { await coordinator.home.load() }
                        }
                    }
                }
        }
    }
}

private struct ConnectedContentView<Content: View>: View {
    let viewModel: HomeViewModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch viewModel.state {
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
                    content()
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
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("homeScreen")
        .task { await viewModel.load() }
    }
}

private struct ConnectionView: View {
    @State private var viewModel: ConnectionViewModel
    let onConnectionChanged: () -> Void
    let done: () -> Void

    init(
        services: AppServices,
        onConnectionChanged: @escaping () -> Void = {},
        done: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ConnectionViewModel(services: services))
        self.onConnectionChanged = onConnectionChanged
        self.done = done
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Server connection") {
                TextField("http://server.local:8080", text: $viewModel.serverURL)
                    .textContentType(.URL)
                TextField("Username", text: $viewModel.username)
                    .textContentType(.username)
                SecureField(
                    viewModel.hasSavedConnection ? "Password (blank keeps saved password)" : "Password",
                    text: $viewModel.password
                )
                .textContentType(.password)

                Button(viewModel.hasSavedConnection ? "Verify & Sign In" : "Verify & Connect") {
                    Task {
                        await viewModel.verifyAndSave()
                        onConnectionChanged()
                    }
                }
                .disabled(viewModel.state == .checking)
                .accessibilityIdentifier("verifyConnection")

                if viewModel.state == .checking {
                    ProgressView("Checking server…")
                } else if viewModel.state == .connected {
                    Text("Server is reachable. Protected requests use HTTP Basic credentials.")
                        .foregroundStyle(.green)
                } else if case .failed(let failure) = viewModel.state {
                    Text(failure.message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("connectionError")
                } else if viewModel.state == .removed {
                    Text("Connection removed.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Network and security") {
                Text("HTTP Basic credentials are not encrypted by HTTP. Use HTTP only on a trusted local network or Tailscale. HTTPS uses normal system certificate validation; a direct local or Tailscale connection does not need an HTTPS certificate.")
                Text("Allow Monekar to access your local network when iOS or iPadOS asks. If access is denied, enable it in Settings > Privacy & Security > Local Network.")
            }

            if viewModel.hasSavedConnection {
                Section {
                    Button("Remove connection", role: .destructive) {
                        Task {
                            await viewModel.removeConnection()
                            onConnectionChanged()
                        }
                    }
                    .accessibilityIdentifier("removeConnection")
                }
            }

            Button("Done", action: done)
                .accessibilityIdentifier("closeConnection")
        }
        .padding()
        .navigationTitle("Connection")
        .accessibilityIdentifier("connectionScreen")
    }
}
