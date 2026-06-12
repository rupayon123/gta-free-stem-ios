import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label(session.text("browse"), systemImage: "magnifyingglass") }
            SavedView()
                .tabItem { Label(session.text("saved"), systemImage: "bookmark") }
            SubmitView()
                .tabItem { Label(session.text("support"), systemImage: "plus.message") }
            SettingsView()
                .tabItem { Label(session.text("settings"), systemImage: "gearshape") }
        }
        .tint(Brand.coral)
    }
}
