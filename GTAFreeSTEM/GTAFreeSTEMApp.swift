import BackgroundTasks
import SwiftData
import SwiftUI

enum AppRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }
}

@main
struct GTAFreeSTEMApp: App {
    nonisolated private static let appRefreshIdentifier = "com.rupayonhaldar.gtafreestem.hunt.refresh"
    nonisolated private static let refreshMinInterval: TimeInterval = 60 * 60 * 3
    nonisolated private static let scheduleMinInterval: TimeInterval = 60 * 15
    nonisolated private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            OpportunityCacheRecord.self,
            SavedHuntRecord.self,
            SeenOpportunityRecord.self
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to initialize shared model container: \(error)")
        }
    }()
    private static let scheduleState = AppRefreshScheduleState()

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
                .modelContainer(Self.sharedModelContainer)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Self.scheduleAppRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(Self.appRefreshIdentifier)) {
            let context = ModelContext(Self.sharedModelContainer)
            await opportunities.refresh(cache: context, prioritized: false, notifyOnNewMatches: true)
            Self.scheduleAppRefresh()
        }
    }

    nonisolated private static func scheduleAppRefresh() {
        let now = Date()
        Task {
            guard await Self.scheduleState.claimSubmission(now: now, minimumInterval: Self.scheduleMinInterval) else {
                return
            }

            let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: refreshMinInterval)
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                await Self.scheduleState.clearSubmission(at: now)
                return
            }
        }
    }
}

private actor AppRefreshScheduleState {
    private var lastScheduledAt: Date?

    func claimSubmission(now: Date, minimumInterval: TimeInterval) -> Bool {
        if let lastScheduledAt,
           now.timeIntervalSince(lastScheduledAt) < minimumInterval {
            return false
        }

        lastScheduledAt = now
        return true
    }

    func clearSubmission(at date: Date) {
        if lastScheduledAt == date {
            lastScheduledAt = nil
        }
    }
}
