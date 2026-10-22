import SwiftUI

struct SettingsView: View {
    let services: AppServices

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ConnectionView(services: services)
                } label: {
                    Label("Connection", systemImage: "network")
                }
                .accessibilityIdentifier("showConnection")

                NavigationLink {
                    LibraryScanView(viewModel: services.libraryScan)
                } label: {
                    Label("Library Scan", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("showLibraryScan")
            }
            .navigationTitle("Settings")
        }
    }
}
