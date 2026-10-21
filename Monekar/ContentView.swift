import SwiftUI

struct ContentView: View {
    @State private var coordinator: AppCoordinator

    init(services: AppServices) {
        _coordinator = State(initialValue: AppCoordinator(services: services))
    }

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.path) {
            HomeView(viewModel: coordinator.home)
                .navigationTitle("Monekar")
                .toolbar {
                    Button("Connection", systemImage: "network") {
                        coordinator.showConnection()
                    }
                    .accessibilityIdentifier("showConnection")
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .connection:
                        ConnectionView(state: coordinator.home.state) {
                            coordinator.pop()
                        }
                    }
                }
        }
    }
}

private struct HomeView: View {
    let viewModel: HomeViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading connection…")
            case .empty:
                ContentUnavailableView(
                    "No server configured",
                    systemImage: "network",
                    description: Text("Set MonekarServerURL in the app configuration to connect to monekar-server.")
                )
            case .loaded(let summary):
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.largeTitle)
                    Text("Ready to connect")
                        .font(.title)
                    Text(summary.serverURL.host() ?? "monekar-server")
                    Text(summary.hasCredential ? "Credential available" : "Sign-in required")
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
        .padding()
        .accessibilityIdentifier("homeScreen")
        .task { await viewModel.load() }
    }
}

private struct ConnectionView: View {
    let state: LoadState<ConnectionSummary>
    let done: () -> Void

    var body: some View {
        Form {
            if case .loaded(let summary) = state {
                LabeledContent("Server", value: summary.serverURL.host() ?? "monekar-server")
                LabeledContent("Authentication", value: summary.hasCredential ? "Credential available" : "Sign-in required")
            } else {
                Text("Configure MonekarServerURL to use your monekar-server instance. Credentials are stored in Keychain.")
            }
            Button("Done", action: done)
                .accessibilityIdentifier("closeConnection")
        }
        .padding()
        .navigationTitle("Connection")
        .accessibilityIdentifier("connectionScreen")
    }
}
