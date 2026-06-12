import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct GTAFreeSTEMApp: App {
    nonisolated private static let appRefreshIdentifier = "com.rupayonhaldar.gtafreestem.hunt.refresh"

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionStore()
    @StateObject private var opportunities = OpportunityStore(api: APIClient())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(opportunities)
                .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
                .environment(\.layoutDirection, session.language.layoutDirection)
                .preferredColorScheme(session.colorScheme)
                .modelContainer(for: [OpportunityCacheRecord.self, SavedHuntRecord.self, SeenOpportunityRecord.self])
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Self.scheduleAppRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(Self.appRefreshIdentifier)) {
            await opportunities.refreshForBackground()
            Self.scheduleAppRefresh()
        }
    }

    nonisolated private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 3)
        try? BGTaskScheduler.shared.submit(request)
    }
}
