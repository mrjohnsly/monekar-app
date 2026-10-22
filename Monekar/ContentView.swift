import SwiftUI

struct ContentView: View {
    let services: AppServices
    @State private var imageViewerSelection: ImageViewerSelection?

    var body: some View {
        TabView {
            Tab {
                ModelsView(services: services, onOpenImage: openImage)
                    .id(services.connectionRevision)
            } label: {
                Label("Models", systemImage: "person")
            }

            Tab {
                FavouritesView(services: services, onOpenImage: openImage)
                    .id(services.connectionRevision)
            } label: {
                Label("Favourites", systemImage: "heart")
            }

            Tab {
                TagsView(services: services, onOpenImage: openImage)
                    .id(services.connectionRevision)
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Tab {
                SettingsView(services: services)
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: services.connectionRevision) {
            imageViewerSelection = nil
        }
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
