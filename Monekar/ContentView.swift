import SwiftUI

struct ContentView: View {
    @Environment(AppServices.self) private var services
    @State var models: WindowModels
    @State var presentation: ImagePresentation

    var body: some View {
        let browsing = models.browsing
        TabView {
            Tab {
                ModelsView()
                    .id(browsing.revision)
            } label: {
                Label("Models", systemImage: "person")
            }

            Tab {
                FavouritesView()
                    .id(browsing.revision)
            } label: {
                Label("Favourites", systemImage: "heart")
            }

            Tab {
                TagsView()
                    .id(browsing.revision)
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Tab {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: services.connectionRevision) {
            presentation.dismiss()
            models.connection.synchronizeConnection()
        }
        .toolbar(presentation.selection == nil ? .automatic : .hidden)
        .overlay {
            if let selection = presentation.selection {
                ImageViewer(selection: selection, selectedIndex: selection.initialIndex)
                    .id(selection.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .ignoresSafeArea()
            }
        }
        .environment(models)
        .environment(presentation)
    }
}
