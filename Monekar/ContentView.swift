import SwiftUI

struct ContentView: View {
    let services: AppServices
    @State private var imageViewerSelection: ImageViewerSelection?

    var body: some View {
        TabView {
            Tab {
                AppNavigationView(services: services, onOpenImage: openImage) { coordinator in
                    ModelsView(coordinator: coordinator)
                        .id(ObjectIdentifier(coordinator.people))
                }
            } label: {
                Label("Models", systemImage: "person")
            }

            Tab {
                AppNavigationView(services: services, onOpenImage: openImage) { coordinator in
                    ImageFeedView(
                        title: "Favourites", viewModel: coordinator.favourites,
                        services: services, onOpenImage: openImage
                    )
                    .id(ObjectIdentifier(coordinator.favourites))
                }
            } label: {
                Label("Favourites", systemImage: "heart")
            }

            Tab {
                AppNavigationView(services: services, onOpenImage: openImage) { coordinator in
                    TagsView(coordinator: coordinator)
                        .id(ObjectIdentifier(coordinator.tags))
                }
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Tab {
                AppNavigationView(services: services, onOpenImage: openImage) { coordinator in
                    List {
                        Button("Connection", systemImage: "network") {
                            coordinator.showConnection()
                        }
                        .accessibilityIdentifier("showConnection")
                        NavigationLink(value: AppRoute.libraryScan) {
                            Label("Library Scan", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("showLibraryScan")
                    }
                    .navigationTitle("Settings")
                }
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbar(imageViewerSelection == nil ? .automatic : .hidden)
        .overlay {
            if let selection = imageViewerSelection {
                ImageViewer(selection: selection, services: services) {
                    imageViewerSelection = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .ignoresSafeArea()
            }
        }
    }

    private func openImage(_ selection: ImageViewerSelection) {
        imageViewerSelection = selection
    }
}

private struct AppNavigationView<Content: View>: View {
    @State private var coordinator: AppCoordinator
    let onOpenImage: (ImageViewerSelection) -> Void
    let content: (AppCoordinator) -> Content

    init(
        services: AppServices,
        onOpenImage: @escaping (ImageViewerSelection) -> Void,
        @ViewBuilder content: @escaping (AppCoordinator) -> Content
    ) {
        _coordinator = State(initialValue: AppCoordinator(services: services))
        self.onOpenImage = onOpenImage
        self.content = content
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.path) {
            content(coordinator)
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
