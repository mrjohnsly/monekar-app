import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ConnectionView()
                } label: {
                    Label("Connection", systemImage: "network")
                }
                .accessibilityIdentifier("showConnection")

                NavigationLink {
                    LibraryScanView()
                } label: {
                    Label("Library Scan", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("showLibraryScan")
            }
            .navigationTitle("Settings")
        }
    }
}
