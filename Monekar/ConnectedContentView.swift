import SwiftUI

struct ConnectedContentView<Content: View>: View {
    let viewModel: HomeViewModel
    @ViewBuilder var content: () -> Content

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
        .task { await viewModel.loadIfNeeded() }
    }
}
