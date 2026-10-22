import SwiftUI

enum SidebarTabs: String, Identifiable, CaseIterable {
    case models
    case favourites
    case settings
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .models: "Models"
        case .favourites: "Favourites"
        case .settings: "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .models: "person"
        case .favourites: "heart"
        case .settings: "gear"
        }
    }
    
    @ContentBuilder
    var content: some View {
        switch self {
        case .models: ModelsView()
        case .favourites: FavouritesView()
        case .settings: Text("Settings")
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ForEach(SidebarTabs.allCases) { tab in
                Tab {
                    tab.content
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
}
