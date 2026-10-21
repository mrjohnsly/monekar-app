import SwiftUI

struct ContentView: View {
    @State private var coordinator: AppCoordinator

    init(services: AppServices) {
        _coordinator = State(initialValue: AppCoordinator(services: services))
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.path) {
            HomeView(coordinator: coordinator)
                .navigationTitle("Monekar")
                .toolbar {
                    Button("Connection", systemImage: "network") {
                        coordinator.showConnection()
                    }
                    .accessibilityIdentifier("showConnection")
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .person(let id):
                        PersonDetailView(
                            viewModel: coordinator.person(id: id),
                            coordinator: coordinator
                        )
                    case .album(let id):
                        AlbumDetailView(
                            viewModel: coordinator.album(id: id),
                            services: coordinator.services
                        )
                    case .connection:
                        ConnectionView(services: coordinator.services) {
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

private struct HomeView: View {
    let coordinator: AppCoordinator

    private var viewModel: HomeViewModel { coordinator.home }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading connection…")
            case .empty:
                ContentUnavailableView(
                    "No server configured",
                    systemImage: "network",
                    description: Text("Set up a local-network or Tailscale server connection to get started.")
                )
            case .loaded(let summary):
                if summary.hasCredential {
                    PeopleView(coordinator: coordinator)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.largeTitle)
                        Text("Sign-in required")
                            .font(.title)
                        Text(summary.serverURL.host() ?? "monekar-server")
                        Text("Open Connection to sign in again.")
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
    let done: () -> Void

    init(services: AppServices, done: @escaping () -> Void) {
        _viewModel = State(initialValue: ConnectionViewModel(services: services))
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
                    Task { await viewModel.verifyAndSave() }
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
                        Task { await viewModel.removeConnection() }
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
