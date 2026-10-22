import SwiftUI

struct ContentView: View {
    let services: AppServices
    @State private var imageViewerSelection: ImageViewerSelection?

    var body: some View {
        TabView {
            Tab {
                AppNavigationView("Models", services: services, onOpenImage: openImage) { coordinator in
                    ModelsView(coordinator: coordinator)
                        .id(ObjectIdentifier(coordinator.people))
                }
            } label: {
                Label("Models", systemImage: "person")
            }

            Tab {
                AppNavigationView("Favourites", services: services, onOpenImage: openImage) { coordinator in
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
                AppNavigationView("Tags", services: services, onOpenImage: openImage) { coordinator in
                    TagsView(coordinator: coordinator)
                        .id(ObjectIdentifier(coordinator.tags))
                }
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Tab {
                AppNavigationView(
                    "Settings", services: services, requiresConnection: false, onOpenImage: openImage
                ) { coordinator in
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
