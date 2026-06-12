import SwiftUI

@main
struct GTAFreeSTEMApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var opportunities = OpportunityStore(api: APIClient())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(opportunities)
        }
    }
}
