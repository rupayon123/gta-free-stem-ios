import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "magnifyingglass") }
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
            SubmitView()
                .tabItem { Label("Submit", systemImage: "plus.message") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Brand.blue)
    }
}
