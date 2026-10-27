import XCTest
@testable import GTAFreeSTEM
import SwiftData

private func makeAppTestModelContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        OpportunityCacheRecord.self,
        SavedHuntRecord.self,
        SeenOpportunityRecord.self,
        SavedOpportunityRecord.self
    ])
    return try ModelContainer(for: schema, configurations: configuration)
}

private func bundledSnapshotTestNow() throws -> Date {
    let bundled = try LocalOpportunitySnapshot.loadFull()
    let dataTime = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated)).addingTimeInterval(3_600)
    let publicationTime = FeedPublicationRevision.date(from: bundled.publicationRevision)?.addingTimeInterval(60) ?? dataTime
    return max(dataTime, publicationTime)
}

final class APIClientTests: XCTestCase {
    @MainActor
    func testRealCatalogueResponsivenessDiagnostic() throws {
        let clock = { ProcessInfo.processInfo.systemUptime }
        let start = clock()
        let feed = try LocalOpportunitySnapshot.loadFull()
        print("GTA_PERF decode_validate_ms=\((clock()-start)*1000) records=\(feed.data.count)")
        XCTAssertGreaterThan(feed.data.count, 1000)
        let now = max(try XCTUnwrap(FeedFreshness.date(from: feed.meta?.lastUpdated)), FeedPublicationRevision.date(from: feed.publicationRevision) ?? .distantPast).addingTimeInterval(60)
        for pass in 0..<3 {
            for query in ["", "robotics", "library", "volunteer", "science"] {
                let begin = clock()
                let result = LocalOpportunitySnapshot.filter(feed.data, query: query, mode: .all, filters: OpportunityFilters(), now: now)
                print("GTA_PERF pass=\(pass) query=\(query.isEmpty ? "ALL" : query) filter_ms=\((clock()-begin)*1000) results=\(result.count)")
            }
            let begin = clock()
            let modes = HomePathwayInventory.availableModes(in: feed.data, now: now)
            print("GTA_PERF pass=\(pass) home_inventory_ms=\((clock()-begin)*1000) modes=\(modes.count)")
        }
        let indexStart = clock()
        let index = LocalOpportunitySnapshot.prepareSearchIndex(feed.data, displayLanguage: .en)
        print("GTA_PERF prepared_index_build_ms=\((clock()-indexStart)*1000) entries=\(index.count)")
        for query in ["robotics", "library", "volunteer", "science"] {
            let begin = clock()
            let indexed = LocalOpportunitySnapshot.filter(feed.data, query: query, mode: .all, filters: OpportunityFilters(), displayLanguage: .en, now: now, preparedSearchIndex: index)
            print("GTA_PERF indexed_query=\(query) filter_ms=\((clock()-begin)*1000) results=\(indexed.count)")
            let original = LocalOpportunitySnapshot.filter(feed.data, query: query, mode: .all, filters: OpportunityFilters(), displayLanguage: .en, now: now)
            XCTAssertEqual(indexed.map(\.id), original.map(\.id), "Indexing must preserve complete source matches and sort order")
        }
        let begin = clock()
        let bytes = try JSONEncoder().encode(feed)
        print("GTA_PERF cache_encode_ms=\((clock()-begin)*1000) bytes=\(bytes.count)")
    }

    @MainActor
    func testRealCataloguePreparationKeepsTheMainActorResponsiveAndLatestQueryWins() async throws {
        let now = try bundledSnapshotTestNow()
        let suite = "GTAFreeSTEMTests.Responsiveness.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OpportunityStore(api: APIClient(), defaults: defaults, now: { now })
        var beats = 0
        var maximumGap = 0.0
        let heartbeat = Task { @MainActor in
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                let current = ProcessInfo.processInfo.systemUptime
                maximumGap = max(maximumGap, current - last)
                last = current
                beats += 1
            }
        }
        defer { heartbeat.cancel() }
        await Task.yield()
        let ready = await store.prepareInitialSnapshot(cache: nil)
        XCTAssertTrue(ready)
        try await Task.sleep(nanoseconds: 20_000_000)
        print("GTA_PERF actual_store_main_actor_max_gap_ms=\(maximumGap*1000) heartbeat_count=\(beats)")
        XCTAssertGreaterThan(beats, 5, "The UI actor must run during catalogue preparation")
        XCTAssertLessThan(maximumGap, 0.75, "Catalogue work must not block UI interactions for a second")
        store.query = "robotics"
        let earlierSearch = Task { @MainActor in await store.prepareInitialSnapshot(cache: nil) }
        await Task.yield()
        store.query = "volunteer"
        let latestSearch = Task { @MainActor in await store.prepareInitialSnapshot(cache: nil) }
        _ = await earlierSearch.value
        _ = await latestSearch.value
        let expected = try await Task.detached(priority: .userInitiated) {
            try LocalOpportunitySnapshot.loadFull().data
        }.value
        let expectedIDs = await Task.detached(priority: .userInitiated) {
            LocalOpportunitySnapshot.filter(expected, query: "volunteer", mode: .all, filters: OpportunityFilters(), now: now).map(\.id)
        }.value
        let expectedCities = Set(expected.filter {
            $0.isExplicitlyFree && LocalOpportunitySnapshot.isCurrentlyAvailable($0, on: now)
        }.map(\.city)).sorted()
        XCTAssertEqual(store.availableFilterCities, expectedCities)
        XCTAssertEqual(store.query, "volunteer")
        XCTAssertEqual(store.opportunities.map(\.id), expectedIDs, "A slower earlier search cannot replace the latest results")
        store.useCurrentLocation(CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832))
        store.filters.region = "York"
        store.filters.age = "12"
        store.useCity("Toronto")
        XCTAssertEqual(store.filters.city, "Toronto")
        XCTAssertEqual(store.filters.region, "All")
        XCTAssertNil(store.filters.latitude)
        XCTAssertNil(store.filters.longitude)
        XCTAssertEqual(store.filters.sort, .date)
        XCTAssertEqual(store.filters.age, "12", "Choosing a city preserves the chosen age")
        XCTAssertEqual(store.query, "volunteer")
    }

    private var testRepositoryRoot: URL {
        let fixtureRoot = Bundle(for: APIClientTests.self)
            .resourceURL?
            .appendingPathComponent("SourceFixtures", isDirectory: true)
        guard
            let fixtureRoot,
            FileManager.default.fileExists(
                atPath: fixtureRoot.appendingPathComponent(".complete").path
            )
        else {
            preconditionFailure("The current-source contract fixtures were not staged into the test bundle.")
        }
        return fixtureRoot
    }

    @MainActor
    func testLocalProfilePersistsAcrossLaunchesAndDeletesCleanly() throws {
        let suiteName = "GTAFreeSTEMTests.LocalProfile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = SessionStore(defaults: defaults, preferredLanguages: ["en"])
        XCTAssertFalse(initial.hasLocalProfile)

        initial.saveLocalProfile(named: "  STEM Explorer  ")
        XCTAssertTrue(initial.hasLocalProfile)
        XCTAssertEqual(initial.displayName, "STEM Explorer")

        let restored = SessionStore(defaults: defaults, preferredLanguages: ["en"])
        XCTAssertTrue(restored.hasLocalProfile)
        XCTAssertEqual(restored.displayName, "STEM Explorer")

        restored.clearLocalProfile()
        XCTAssertFalse(restored.hasLocalProfile)
        XCTAssertEqual(restored.displayName, restored.text("guest"))

        let relaunchedAfterDeletion = SessionStore(defaults: defaults, preferredLanguages: ["en"])
        XCTAssertFalse(relaunchedAfterDeletion.hasLocalProfile)
        XCTAssertEqual(relaunchedAfterDeletion.displayName, relaunchedAfterDeletion.text("guest"))
    }

    @MainActor
    func testBlankLocalProfileNameIsNotSaved() throws {
        let suiteName = "GTAFreeSTEMTests.BlankLocalProfile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let session = SessionStore(defaults: defaults, preferredLanguages: ["en"])
        session.saveLocalProfile(named: "   \n  ")

        XCTAssertFalse(session.hasLocalProfile)
        XCTAssertEqual(session.displayName, session.text("guest"))
    }

    func testClearProfileActionDoesNotUseTheDestructiveSavedDataPath() throws {
        let repoRoot = testRepositoryRoot
        let source = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))
        let buttonStart = try XCTUnwrap(source.range(of: "private var signOutButton"))
        let buttonEnd = try XCTUnwrap(source.range(of: "private var deleteAccountButton", range: buttonStart.lowerBound..<source.endIndex))
        let clearButtonSource = String(source[buttonStart.lowerBound..<buttonEnd.lowerBound])

        XCTAssertTrue(clearButtonSource.contains("clearLocalProfileOnly()"))
        XCTAssertFalse(clearButtonSource.contains("clearLocalProfileAndSaves()"))
    }

    func testGuestSettingsExposeBulkPersonalDataDeletion() throws {
        let repoRoot = testRepositoryRoot
        let source = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))
        let accountCardStart = try XCTUnwrap(source.range(of: "private var accountCard"))
        let accountCardEnd = try XCTUnwrap(
            source.range(of: "private var signOutButton", range: accountCardStart.lowerBound..<source.endIndex)
        )
        let accountCardSource = String(source[accountCardStart.lowerBound..<accountCardEnd.lowerBound])

        XCTAssertTrue(
            accountCardSource.contains("guestDataDeletionButton"),
            "Guests can save opportunities and hunt history, so Settings must expose their bulk deletion action without requiring a profile."
        )
        XCTAssertTrue(source.contains("private var guestDataDeletionButton"))
        XCTAssertTrue(source.contains("session.text(\"deleteLocalData\")"))
        XCTAssertTrue(source.contains("\"localDataDeleted\""))
    }

    func testProfileDeletionCopyDisclosesHuntHistoryInEveryLanguage() throws {
        let historyTermsByLanguage = [
            "en": "hunt history",
            "fr": "historique de recherche",
            "zh": "搜索记录",
            "yue": "搜尋記錄",
            "pa": "ਖੋਜ ਇਤਿਹਾਸ",
            "ur": "تلاش کی سرگزشت",
            "ta": "தேடல் வரலா",
            "tl": "kasaysayan ng paghahanap",
            "es": "historial de busqueda",
            "ar": "سجل البحث",
            "fa": "سابقه جستجو",
            "hi": "खोज इतिहास",
            "pt": "historico de pesquisa",
            "gu": "શોધ ઇતિહાસ",
            "bn": "অনুসন্ধানের ইতিহাস",
            "ja": "検索履歴",
            "ko": "검색 기록",
            "hu": "keresési előzmények"
        ]

        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for language in AppLanguage.allCases {
            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            let historyTerm = try XCTUnwrap(historyTermsByLanguage[language.rawValue])
            for key in ["deleteAccountConfirmation", "accountDeleted"] {
                let value = try XCTUnwrap(strings[key])
                XCTAssertTrue(
                    value.lowercased().contains(historyTerm.lowercased()),
                    "\(language.rawValue).\(key) must disclose that hunt/search history is deleted."
                )
            }
        }

        let repoRoot = testRepositoryRoot
        let source = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))
        XCTAssertTrue(source.contains("session.hasLocalProfile ? \"deleteAccountConfirmation\" : \"deleteLocalData\""))
        XCTAssertTrue(source.contains("session.hasLocalProfile ? \"deleteAccount\" : \"deleteLocalData\""))
    }

    func testOpportunityDecodesFromRailsPayload() throws {
        let json = """
        {
          "data": [{
            "id": "tpl-1",
            "title": "Robotics Club",
            "organization": "Public Library",
            "description": "Build robots.",
            "summary": "Build robots.",
            "category": "Coding & Robotics",
            "city": "Toronto",
            "region": "Toronto",
            "address": "100 Queen St W",
            "latitude": 43.65,
            "longitude": -79.38,
            "startDate": "2026-06-20T12:00:00Z",
            "endDate": null,
            "deadline": null,
            "ageMin": 12,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free to join",
            "sourceUrl": "https://example.com",
            "registrationUrl": "https://example.com/register",
            "status": "active",
            "volunteerHoursEligible": true,
            "coopEligible": false,
            "tags": ["robotics"]
          }],
          "meta": { "activeCount": 1, "lastUpdated": "2026-06-12T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(OpportunityListResponse.self, from: json)
        XCTAssertEqual(payload.data.first?.title, "Robotics Club")
        XCTAssertEqual(payload.meta?.activeCount, 1)
    }

    func testOpportunityDecodesFromSharedPublicFeed() throws {
        let json = """
        {
          "name": "GTA FREE STEM Opportunities public feed",
          "schemaVersion": 1,
          "count": 1,
          "lastDataChange": "2026-06-12",
          "opportunities": [{
            "id": "feed-1",
            "title": "Library Coding Lab",
            "organization": "Public Library",
            "description": "Free coding workshop.",
            "category": "Coding & Robotics",
            "city": "Markham",
            "region": "York",
            "ageMin": 8,
            "ageMax": 12,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com",
            "status": "active",
            "tags": ["coding"],
            "volunteerHoursEligible": false,
            "coopEligible": false
          }]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(OpportunityListResponse.self, from: json)
        XCTAssertEqual(payload.data.first?.title, "Library Coding Lab")
        XCTAssertEqual(payload.meta?.activeCount, 1)
        XCTAssertEqual(payload.meta?.lastUpdated, "2026-06-12")
    }

    func testLaunchUsesBrandedStoryboardInsteadOfBlankGeneratedScreen() throws {
        let repoRoot = testRepositoryRoot
        let project = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"))
        let info = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/Info.plist"))

        XCTAssertTrue(project.contains("UILaunchStoryboardName: LaunchScreen"))
        XCTAssertTrue(info.contains("<key>UILaunchStoryboardName</key>"))
        XCTAssertFalse(info.contains("<key>UILaunchScreen</key>"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("GTAFreeSTEM/LaunchScreen.storyboard").path)
        )
    }

    func testLaunchStoryboardAvoidsDuplicateAnimatedContentDuringHandoff() throws {
        let repoRoot = testRepositoryRoot
        let launchStoryboard = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/LaunchScreen.storyboard"))
        let appSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift"))

        XCTAssertTrue(launchStoryboard.contains("image=\"Logo\""))
        XCTAssertTrue(launchStoryboard.contains("constant=\"220\" id=\"launchLogoWidth\""))
        XCTAssertTrue(launchStoryboard.contains("constant=\"220\" id=\"launchLogoHeight\""))
        XCTAssertTrue(launchStoryboard.contains("constant=\"-38\" id=\"launchLogoCenterY\""))
        XCTAssertFalse(launchStoryboard.contains("launchTitle"))
        XCTAssertFalse(launchStoryboard.contains("launchSubtitle"))
        XCTAssertFalse(launchStoryboard.contains("launchProgress"))
        XCTAssertTrue(appSource.contains("private static let heroLogoSize: CGFloat = 220"))
        XCTAssertTrue(appSource.contains("LaunchScienceField("))
        XCTAssertTrue(appSource.contains("LaunchProgressPanel("))
        XCTAssertTrue(appSource.contains("TimelineView(.animation"))
        XCTAssertTrue(appSource.contains("real progress bar is a sibling"))
        XCTAssertTrue(appSource.contains("LaunchScanTrack(progress: progress"))
        XCTAssertTrue(appSource.contains("let usesHorizontalLayout = proxy.size.width > proxy.size.height"))
        XCTAssertTrue(appSource.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(appSource.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)"))
        XCTAssertTrue(appSource.contains("loadingText: session.text(\"preparingOpportunities\")"))
        XCTAssertFalse(appSource.contains("loadingText: session.text(\"checkingLiveSources\")"))
        XCTAssertTrue(appSource.contains("reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.78)"))
        XCTAssertTrue(appSource.contains(".frame(maxWidth: .infinity)"))
        XCTAssertTrue(appSource.contains(".frame(height: 14)"))
        XCTAssertFalse(appSource.contains("Text(title)"))
        XCTAssertFalse(appSource.contains("detailsCenterY"))
        XCTAssertFalse(appSource.contains(".frame(width: 228, height: 12)"))
        XCTAssertFalse(appSource.contains(".animation(reduceMotion ? nil : .smooth(duration: 0.32), value: progress)"))
        XCTAssertFalse(appSource.contains("gearsPresented ?"))
        XCTAssertFalse(appSource.contains("scaleEffect(hasAppeared ? 1 : 0.84)"))
    }

    func testLaunchProgressCompletesAfterTheInitialSnapshotIsPrepared() throws {
        let repoRoot = testRepositoryRoot
        let appSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift"))
        let storeSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/OpportunityStore.swift"))

        let snapshotOffset = try XCTUnwrap(
            appSource.range(of: "opportunities.prepareInitialSnapshot(cache: context)")
        ).lowerBound
        let completionOffset = try XCTUnwrap(
            appSource.range(of: "launchProgress = 1")
        ).lowerBound
        let handoffOffset = try XCTUnwrap(
            appSource.range(of: "isShowingLaunchExperience = false")
        ).lowerBound
        let launchTaskStart = try XCTUnwrap(
            appSource.range(of: "guard isShowingLaunchExperience else { return }")
        ).lowerBound
        let launchTask = String(appSource[launchTaskStart...handoffOffset])

        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: snapshotOffset),
            appSource.distance(from: appSource.startIndex, to: completionOffset),
            "The launch bar must not complete until a usable local snapshot is prepared."
        )
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: completionOffset),
            appSource.distance(from: appSource.startIndex, to: handoffOffset),
            "The launch bar should finish immediately before interactive content is shown."
        )
        XCTAssertTrue(appSource.contains("progress: displayedProgress"))
        XCTAssertTrue(appSource.contains("LaunchScanTrack(progress: progress"))
        XCTAssertTrue(appSource.contains("max(displayedProgress, boundedProgress)"))
        XCTAssertTrue(appSource.contains("accessibilityIdentifier(\"launch-progress\")"))
        XCTAssertTrue(appSource.contains(".accessibilityValue(\"\\(Int((displayedProgress * 100).rounded()))%\")"))
        XCTAssertTrue(storeSource.contains("Task.detached(priority: .userInitiated)"))
        XCTAssertTrue(storeSource.contains("decodeCachedFullResponse"))
        XCTAssertTrue(storeSource.contains("guard let payload = cachedPayload(from: context)"))
        XCTAssertTrue(
            storeSource.contains("guard let cached = await Self.decodeCachedFullResponse(payload, now: self.now())"),
            "A repeat launch must copy the SwiftData payload on the main actor and decode it off-main so loader motion stays responsive."
        )
        XCTAssertFalse(appSource.contains("scanPosition"))
        XCTAssertFalse(appSource.contains("LaunchScanTrack(position:"))
        XCTAssertFalse(appSource.contains("launchExperienceDuration"))
        XCTAssertFalse(
            launchTask.contains("await opportunities.refresh"),
            "Launch must hand off to an interactive shell instead of waiting on a possibly unavailable network."
        )
        XCTAssertTrue(
            launchTask.contains("600_000_000"),
            "The completed loading state should remain visible for one short handoff beat."
        )
        XCTAssertFalse(
            launchTask.contains("360_000_000") || launchTask.contains("320_000_000"),
            "Launch progress should represent readiness instead of staged display delays."
        )
    }

    func testLaunchAndTabAnimationsHonorReduceMotionAndLaunchUsesStoredDirection() throws {
        let repoRoot = testRepositoryRoot
        let appSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift"))
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))

        XCTAssertTrue(appSource.contains("withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24))"))
        XCTAssertTrue(appSource.contains("withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24))"))
        XCTAssertTrue(appSource.contains("withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32))"))
        XCTAssertTrue(appSource.contains("withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26))"))
        XCTAssertTrue(contentSource.contains(".animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: selectedTab)"))
        XCTAssertEqual(
            contentSource.components(separatedBy: "isActive: store.isLoading && !reduceMotion").count - 1,
            1
        )

        let launchBranch = try XCTUnwrap(appSource.range(of: "if isShowingLaunchExperience"))
        let localeEnvironment = try XCTUnwrap(appSource.range(of: ".environment(\\.locale"))
        let layoutEnvironment = try XCTUnwrap(appSource.range(of: ".environment(\\.layoutDirection"))
        XCTAssertLessThan(launchBranch.lowerBound, localeEnvironment.lowerBound)
        XCTAssertLessThan(launchBranch.lowerBound, layoutEnvironment.lowerBound)
        XCTAssertTrue(appSource.contains("Locale(identifier: session.language.localeIdentifier)"))
        XCTAssertTrue(appSource.contains("session.language.layoutDirection"))
    }

    func testScreenshotQueryLaunchOptionIsExplicitAndSafe() {
        XCTAssertEqual(
            AppLaunchConfiguration.screenshotQuery(arguments: ["GTAFreeSTEM", "-start-opportunities", "-screenshot-query", "robotics"]),
            "robotics"
        )
        XCTAssertEqual(
            AppLaunchConfiguration.screenshotQuery(arguments: ["GTAFreeSTEM", "-SCREENSHOT-QUERY", " STEM clubs "]),
            "STEM clubs"
        )
        XCTAssertEqual(
            AppLaunchConfiguration.screenshotQuery(
                arguments: ["GTAFreeSTEM"],
                environment: [AppLaunchConfiguration.screenshotQueryEnvironmentKey: " robotics "]
            ),
            "robotics"
        )
        XCTAssertNil(AppLaunchConfiguration.screenshotQuery(arguments: ["GTAFreeSTEM", "-screenshot-query"]))
        XCTAssertNil(AppLaunchConfiguration.screenshotQuery(arguments: ["GTAFreeSTEM", "-screenshot-query", "   "]))
    }

    func testScreenshotCaptureModeRequiresAnExplicitEnvironmentFlag() {
        XCTAssertEqual(AppLaunchConfiguration.screenshotReadyNonceEnvironmentKey, "GTA_FREE_STEM_SCREENSHOT_READY_NONCE")
        XCTAssertEqual(AppLaunchConfiguration.screenshotReadyMarkerFilename, "gta-free-stem-screenshot-ready")
        XCTAssertEqual(AppLaunchConfiguration.screenshotModeArgument, "-screenshot-mode")
        XCTAssertEqual(AppLaunchConfiguration.screenshotReadyNonceArgument, "-screenshot-ready-nonce")
        XCTAssertTrue(
            AppLaunchConfiguration.isScreenshotCapture(
                environment: [AppLaunchConfiguration.screenshotModeEnvironmentKey: "1"]
            )
        )
        XCTAssertTrue(
            AppLaunchConfiguration.isScreenshotCapture(
                environment: [AppLaunchConfiguration.screenshotModeEnvironmentKey: " TRUE "]
            )
        )
        XCTAssertFalse(AppLaunchConfiguration.isScreenshotCapture(environment: [:]))
        XCTAssertTrue(
            AppLaunchConfiguration.isScreenshotCapture(arguments: ["GTAFreeSTEM", "-screenshot-mode"])
        )
        XCTAssertFalse(
            AppLaunchConfiguration.isScreenshotCapture(
                environment: [AppLaunchConfiguration.screenshotModeEnvironmentKey: "0"]
            )
        )
    }

    @MainActor
    func testScreenshotSnapshotUsesOnlyAppOwnedSampleListingsWithoutStartingNetwork() async {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let feedURL = URL(string: "https://example.com/opportunities.json")!
        let client = APIClient(feedURL: feedURL, session: makeURLSessionForStub())
        let store = OpportunityStore(api: client)

        let isReady = await store.prepareScreenshotSnapshot()

        XCTAssertTrue(isReady)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
        XCTAssertEqual(store.opportunities.count, 4)
        XCTAssertTrue(store.opportunities.allSatisfy { $0.title.hasPrefix("Sample:") })
        XCTAssertTrue(store.opportunities.allSatisfy { $0.organization == "GTA FREE STEM Sample Studio" })
        XCTAssertTrue(store.opportunities.allSatisfy { $0.sourceUrl == "https://gta-free-stem.pages.dev/support/" })
        XCTAssertFalse(store.opportunities.contains { $0.organization.contains("Library") })
    }

    func testDefaultClientUsesTheCurrentPublicFeedSource() {
        let client = APIClient()

        XCTAssertEqual(client.feedURL, APIClient.primaryPublicFeedURL)
        XCTAssertEqual(client.feedURL.host, "raw.githubusercontent.com")
        XCTAssertEqual(APIClient.fallbackPublicFeedURL.host, "cdn.jsdelivr.net")
    }

    func testAPIClientAcceptsAProductionSizedPublicFeed() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let feedURL = URL(string: "https://example.com/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let largeDescription = String(repeating: "fresh STEM opportunity ", count: 260_000)
        let rightsTimestamp = currentFeedTimestamp()
        let payload = try JSONEncoder().encode(
            OpportunityListResponse(
                data: [
                    approvedProviderOpportunity(
                        id: "production-sized",
                        title: "Production Feed",
                        description: largeDescription
                    )
                ],
                meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: currentFeedTimestamp()),
                sourceHealth: sourceHealth(publishedCount: 1),
                contentRights: OpportunityListResponse.ContentRights(
                    termsVerifiedAt: rightsTimestamp,
                    sources: [
                        approvedProviderRightsSource(
                            records: 1,
                            termsVerifiedAt: rightsTimestamp
                        )
                    ],
                    restrictedOpportunityIDs: []
                )
            )
        )

        XCTAssertGreaterThan(payload.count, 5_000_000)
        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)

        let response = try await client.opportunities(query: "", mode: .all, filters: OpportunityFilters())
        XCTAssertEqual(response.data.map(\.id), ["production-sized"])
    }

    func testFreshnessPolicyRejectsMissingMalformedFutureAndStaleMetadata() {
        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let boundary = ISO8601DateFormatter().string(from: now.addingTimeInterval(-FeedFreshness.maximumRemoteFeedAge))
        let justOverBoundary = ISO8601DateFormatter().string(from: now.addingTimeInterval(-FeedFreshness.maximumRemoteFeedAge - 1))
        let future = ISO8601DateFormatter().string(from: now.addingTimeInterval(1))

        XCTAssertTrue(FeedFreshness.isCurrent(boundary, now: now))
        XCTAssertFalse(FeedFreshness.isCurrent(justOverBoundary, now: now))
        XCTAssertFalse(FeedFreshness.isCurrent(nil, now: now))
        XCTAssertFalse(FeedFreshness.isCurrent("not-a-date", now: now))
        XCTAssertFalse(FeedFreshness.isCurrent(future, now: now))
    }

    func testSourceHealthRejectsZeroSuccessAndInvalidThresholds() throws {
        let baseline = try encodedFeed(id: "health-validation", lastUpdated: "2026-08-20T12:00:00Z")
        let invalidReports: [(String, [String: Any])] = [
            ("library", ["successfulPages": 0, "pageSuccessRatio": 0, "minimumPageSuccessRatio": 0]),
            ("library", ["minimumPageSuccessRatio": -0.1]),
            ("library", ["minimumPageSuccessRatio": 1.1, "pageSuccessRatio": 1.1]),
            ("library", ["pageSuccessRatio": 1.1]),
            ("library", ["minimumAcceptedListings": 0]),
            ("library", ["minimumAcceptedListings": -1]),
            ("discovery", ["successfulSources": 0, "sourceSuccessRatio": 0, "minimumSourceSuccessRatio": 0]),
            ("discovery", ["minimumSourceSuccessRatio": -0.1]),
            ("discovery", ["minimumSourceSuccessRatio": 1.1, "sourceSuccessRatio": 1.1]),
            ("discovery", ["sourceSuccessRatio": 1.1])
        ]

        for (section, changes) in invalidReports {
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
            var health = try XCTUnwrap(envelope["sourceHealth"] as? [String: Any])
            var report = try XCTUnwrap(health[section] as? [String: Any])
            report.merge(changes) { _, replacement in replacement }
            health[section] = report
            envelope["sourceHealth"] = health
            let response = try JSONDecoder().decode(
                OpportunityListResponse.self,
                from: JSONSerialization.data(withJSONObject: envelope)
            )

            XCTAssertFalse(response.hasHealthyDeclaredSources, "Invalid \(section) report: \(changes)")
            XCTAssertFalse(response.permitsDestructiveSavedReconciliation)
        }
        let valid = try JSONDecoder().decode(OpportunityListResponse.self, from: baseline)
        XCTAssertTrue(valid.hasHealthyDeclaredSources)
    }

    func testChunkedOversizedFeedCancelsBeforeEOFAndUsesFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let now = FeedFreshness.date(from: "2026-08-20T12:00:00Z")!
        let primary = URL(string: "https://primary.example/chunked.json")!
        let fallback = URL(string: "https://fallback.example/chunked.json")!
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub(), now: { now })
        URLProtocolStub.register(
            responseFor: primary,
            chunks: Array(repeating: Data(repeating: 32, count: 2_000_000), count: 5) + [Data([32])],
            holdCompletion: true
        )
        URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: try encodedFeed(id: "bounded-fallback", lastUpdated: "2026-08-20T12:00:00Z"))
        let finished = expectation(description: "Oversized input is rejected without waiting for EOF")
        let request = Task {
            defer { finished.fulfill() }
            return try await client.opportunityFeed()
        }

        await fulfillment(of: [finished], timeout: 10)
        let stoppedBeforeEOF = URLProtocolStub.stopCount(for: primary) > 0 && !URLProtocolStub.didFinish(for: primary)
        // Release even on failure so a buffering implementation cannot leak a task.
        URLProtocolStub.releaseCompletion(for: primary)
        let response = try await request.value

        XCTAssertTrue(stoppedBeforeEOF)
        XCTAssertEqual(response.data.map(\.id), ["bounded-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount(for: fallback), 1)
    }

    func testOversizedDeclaredLengthCancelsBeforeReadingBody() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let now = FeedFreshness.date(from: "2026-08-20T12:00:00Z")!
        let primary = URL(string: "https://primary.example/declared-length.json")!
        let fallback = URL(string: "https://fallback.example/declared-length.json")!
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub(), now: { now })
        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: Data("unexpected body".utf8), headers: ["Content-Type": "application/json", "Content-Length": "10000001"], holdBody: true)
        URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: try encodedFeed(id: "header-fallback", lastUpdated: "2026-08-20T12:00:00Z"))
        let finished = expectation(description: "Oversized declared length is rejected before the body")
        let request = Task {
            defer { finished.fulfill() }
            return try await client.opportunityFeed()
        }

        await fulfillment(of: [finished], timeout: 5)
        let stoppedBeforeBody = URLProtocolStub.stopCount(for: primary) > 0 && URLProtocolStub.deliveredBytes(for: primary) == 0
        URLProtocolStub.releaseBody(for: primary)
        let response = try await request.value

        XCTAssertTrue(stoppedBeforeBody)
        XCTAssertEqual(response.data.map(\.id), ["header-fallback"])
    }

    func testInsecureFinalResponseURLUsesSecureFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let now = FeedFreshness.date(from: "2026-08-20T12:00:00Z")!
        let primary = URL(string: "https://primary.example/final-url.json")!
        let fallback = URL(string: "https://fallback.example/final-url.json")!
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub(), now: { now })
        URLProtocolStub.register(
            responseFor: primary,
            statusCode: 200,
            body: try encodedFeed(id: "insecure-response", lastUpdated: "2026-08-20T12:00:00Z"),
            finalResponseURL: URL(string: "http://primary.example/redirected.json")!
        )
        URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: try encodedFeed(id: "secure-fallback", lastUpdated: "2026-08-20T12:00:00Z"))

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["secure-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount(for: fallback), 1)
    }

    func testCancelledPrimaryRequestDoesNotTryMirror() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let primary = URL(string: "https://primary.example/cancelled.json")!
        let fallback = URL(string: "https://fallback.example/cancelled.json")!
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub())
        URLProtocolStub.register(responseFor: primary, errorCode: .cancelled)
        URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: try encodedFeed(id: "must-not-load", lastUpdated: currentFeedTimestamp()))

        do {
            _ = try await client.opportunityFeed()
            XCTFail("Cancellation must propagate without retrieving the mirror.")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertEqual(URLProtocolStub.requestCount(for: primary), 1)
        XCTAssertEqual(URLProtocolStub.requestCount(for: fallback), 0)
    }

    func testCancellationBeforeStartingDoesNotCreateARequest() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let primary = URL(string: "https://primary.example/pre-cancelled.json")!
        let fallback = URL(string: "https://fallback.example/pre-cancelled.json")!
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub())
        let gate = APIRequestStartGate()
        let request = Task {
            await gate.wait()
            return try await client.opportunityFeed()
        }
        request.cancel()
        await gate.release()
        do {
            _ = try await request.value
            XCTFail("A pre-cancelled operation must not start transport.")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
    }

    func testCancellationAndCompletionRaceFinishesOnceWithoutMirror() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let now = FeedFreshness.date(from: "2026-08-20T12:00:00Z")!
        for index in 0..<18 {
            let primary = URL(string: "https://primary.example/race-\(index).json")!
            let fallback = URL(string: "https://fallback.example/race-\(index).json")!
            let expectedID = "race-\(index)"
            let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: makeURLSessionForStub(), now: { now })
            URLProtocolStub.register(responseFor: primary, statusCode: 200, body: try encodedFeed(id: expectedID, lastUpdated: "2026-08-20T12:00:00Z"), holdResponse: true)
            URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: try encodedFeed(id: "must-not-load", lastUpdated: "2026-08-20T12:00:00Z"))
            let finished = expectation(description: "Race \(index) finishes exactly once")
            finished.assertForOverFulfill = true
            let request = Task {
                defer { finished.fulfill() }
                return try await client.opportunityFeed()
            }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while URLProtocolStub.requestCount(for: primary) == 0 && clock.now < deadline { await Task.yield() }
            XCTAssertEqual(URLProtocolStub.requestCount(for: primary), 1)
            if index % 3 == 0 {
                request.cancel()
                URLProtocolStub.releaseResponse(for: primary)
            } else if index % 3 == 1 {
                URLProtocolStub.releaseResponse(for: primary)
                await fulfillment(of: [finished], timeout: 5)
                request.cancel()
            } else {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { request.cancel() }
                    group.addTask { URLProtocolStub.releaseResponse(for: primary) }
                    await group.waitForAll()
                }
            }
            if index % 3 != 1 { await fulfillment(of: [finished], timeout: 5) }
            do {
                let response = try await request.value
                XCTAssertEqual(response.data.map(\.id), [expectedID])
                XCTAssertNotEqual(index % 3, 0, "Cancellation-first control must not succeed.")
            } catch {
                XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
                XCTAssertNotEqual(index % 3, 1, "Completion-first control must succeed.")
            }
            XCTAssertEqual(URLProtocolStub.requestCount(for: fallback), 0)
        }
    }

    func testMalformedSuppliedScheduleAndStatusFieldsRejectTheFeed() throws {
        let baseline = try encodedFeed(id: "schedule-validation", lastUpdated: "2026-08-20T12:00:00Z")
        let malformedValues: [(String, Any)] = [
            ("startDate", 123), ("endDate", false), ("deadline", ["date": "2026-08-20"]),
            ("startDate", ""), ("endDate", "not-a-date"), ("deadline", "2026-02-30"),
            ("endDate", "2026-02-30T12:00:00Z"), ("endDate", "2026-08-20T25:00:00Z"),
            ("status", 123), ("status", NSNull()), ("status", "   ")
        ]

        for (field, value) in malformedValues {
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
            var rows = try XCTUnwrap(envelope["data"] as? [[String: Any]])
            rows[0][field] = value
            envelope["data"] = rows
            let malformed = try JSONSerialization.data(withJSONObject: envelope)

            XCTAssertThrowsError(
                try JSONDecoder().decode(OpportunityListResponse.self, from: malformed),
                "Malformed supplied \(field) must not become an active undated record."
            )
        }
    }

    func testAbsentSchedulesAndValidExpiryValuesRemainSupported() throws {
        let baseline = try encodedFeed(id: "valid-schedule", lastUpdated: "2026-08-20T12:00:00Z")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
        var rows = try XCTUnwrap(envelope["data"] as? [[String: Any]])
        for field in ["startDate", "endDate", "deadline", "status"] {
            rows[0].removeValue(forKey: field)
        }
        envelope["data"] = rows
        let absent = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)
        )
        XCTAssertNil(absent.data.first?.endDate)
        XCTAssertEqual(absent.data.first?.status, "active")

        rows[0]["startDate"] = NSNull()
        rows[0]["deadline"] = NSNull()
        rows[0]["endDate"] = "2026-11-01"
        envelope["data"] = rows
        let dateOnly = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)
        )
        let event = try XCTUnwrap(dateOnly.data.first)
        XCTAssertNil(event.startDate)
        XCTAssertNil(event.deadline)
        XCTAssertTrue(LocalOpportunitySnapshot.isCurrentlyAvailable(event, on: FeedFreshness.date(from: "2026-11-02T04:59:59Z")!))
        XCTAssertFalse(LocalOpportunitySnapshot.isCurrentlyAvailable(event, on: FeedFreshness.date(from: "2026-11-02T05:00:00Z")!))

        rows[0]["endDate"] = "2026-11-01T01:30:00-04:00"
        envelope["data"] = rows
        let timestamp = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)
        )
        XCTAssertEqual(timestamp.data.first?.endDate, "2026-11-01T01:30:00-04:00")
        XCTAssertFalse(LocalOpportunitySnapshot.isCurrentlyAvailable(
            try XCTUnwrap(timestamp.data.first), on: FeedFreshness.date(from: "2026-11-01T05:30:01Z")!
        ))

        rows[0]["startDate"] = "2026-11-01T05:30:00.123Z"
        rows[0]["deadline"] = "2026-11-01T05:30:00.123Z"
        rows[0]["endDate"] = "2026-11-03T05:30:00.123Z"
        envelope["data"] = rows
        let ongoing = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)
        )
        let ongoingEvent = try XCTUnwrap(ongoing.data.first)
        XCTAssertEqual(ongoingEvent.startDate, "2026-11-01T05:30:00.123Z")
        XCTAssertFalse(LocalOpportunitySnapshot.hasDistinctRegistrationDeadline(ongoingEvent))
        XCTAssertTrue(LocalOpportunitySnapshot.isCurrentlyAvailable(ongoingEvent, on: FeedFreshness.date(from: "2026-11-02T12:00:00Z")!))

        rows[0]["status"] = "unknown-future-status"
        envelope["data"] = rows
        let unavailable = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: JSONSerialization.data(withJSONObject: envelope)
        )
        XCTAssertFalse(LocalOpportunitySnapshot.isCurrentlyAvailable(try XCTUnwrap(unavailable.data.first)))
    }

    func testStalePrimaryFeedUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/opportunities.json")!
        let fallback = URL(string: "https://fallback.example/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: primary, fallbackFeedURLs: [fallback], session: session, now: { now })
        let stalePayload = try encodedFeed(id: "stale", lastUpdated: "2026-07-01T12:00:00Z")
        let freshPayload = try encodedFeed(id: "fresh", lastUpdated: "2026-08-06T12:00:00Z")

        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: stalePayload)
        URLProtocolStub.register(responseFor: fallback, statusCode: 200, body: freshPayload)

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["fresh"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testDuplicatePrimaryFeedIDsUseFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/duplicate-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/duplicate-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )

        URLProtocolStub.register(
            responseFor: primary,
            statusCode: 200,
            body: try encodedFeed(ids: ["duplicate", "duplicate"], lastUpdated: "2026-08-06T12:00:00Z")
        )
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testBlankPrimaryFeedIDUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/blank-id-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/blank-id-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )

        URLProtocolStub.register(
            responseFor: primary,
            statusCode: 200,
            body: try encodedFeed(ids: ["   "], lastUpdated: "2026-08-06T12:00:00Z")
        )
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testUnhealthyDeclaredPrimaryFeedUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/unhealthy-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/unhealthy-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )

        URLProtocolStub.register(
            responseFor: primary,
            statusCode: 200,
            body: try encodedFeed(
                ids: ["publisher-incident"],
                lastUpdated: "2026-08-06T12:00:00Z",
                sourceHealthStatus: "unhealthy"
            )
        )
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testDeclaredHealthyButMateriallyPartialPrimaryFeedUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/partial-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/partial-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )

        URLProtocolStub.register(
            responseFor: primary,
            statusCode: 200,
            body: try encodedFeed(
                ids: ["only-one-record"],
                lastUpdated: "2026-08-06T12:00:00Z",
                sourceHealthStatus: "healthy",
                minimumAcceptedListings: 10
            )
        )
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testPrimaryFeedMissingSourceHealthUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/missing-health-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/missing-health-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )
        let missingHealth = try JSONEncoder().encode(
            OpportunityListResponse(
                data: [opportunity(id: "partial-without-health", title: "Partial")],
                meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: "2026-08-06T12:00:00Z")
            )
        )

        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: missingHealth)
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testPrimaryFeedMissingContentRightsUsesFreshFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/missing-rights-opportunities.json")!
        let fallback = URL(string: "https://fallback.example/missing-rights-opportunities.json")!
        let client = APIClient(
            feedURL: primary,
            fallbackFeedURLs: [fallback],
            session: makeURLSessionForStub(),
            now: { now }
        )
        let missingRights = try JSONEncoder().encode(
            OpportunityListResponse(
                data: [opportunity(id: "without-rights", title: "Missing Rights")],
                meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: "2026-08-06T12:00:00Z"),
                sourceHealth: sourceHealth(publishedCount: 1)
            )
        )

        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: missingRights)
        URLProtocolStub.register(
            responseFor: fallback,
            statusCode: 200,
            body: try encodedFeed(id: "valid-fallback", lastUpdated: "2026-08-06T12:00:00Z")
        )

        let response = try await client.opportunityFeed()

        XCTAssertEqual(response.data.map(\.id), ["valid-fallback"])
        XCTAssertEqual(URLProtocolStub.requestCount, 2)
    }

    func testMissingFreshnessMetadataDoesNotCountAsALivePrimaryFeed() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let now = FeedFreshness.date(from: "2026-08-06T12:00:00Z")!
        let primary = URL(string: "https://primary.example/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: primary, session: session, now: { now })

        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: try encodedFeed(id: "missing-date", lastUpdated: nil))

        do {
            _ = try await client.opportunityFeed()
            XCTFail("A remote feed without declared freshness must not replace an on-device cache.")
        } catch {
            XCTAssertEqual(URLProtocolStub.requestCount, 1)
        }
    }

    func testUnknownPublicFeedEnvelopeIsRejected() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let feedURL = URL(string: "https://example.com/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: #"{"schemaVersion": 1, "notOpportunities": []}"#.data(using: .utf8)!
        )

        do {
            _ = try await client.opportunities(query: "", mode: .all, filters: OpportunityFilters())
            XCTFail("A malformed public-feed envelope must not replace the last known-good cache with an empty result.")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testDeclaredFeedCountMustMatchDecodedPayload() throws {
        let response = OpportunityListResponse(
            data: [opportunity(id: "one", title: "One")],
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: currentFeedTimestamp())
        )
        let encoded = try JSONEncoder().encode(response)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        envelope["opportunities"] = envelope.removeValue(forKey: "data")
        envelope.removeValue(forKey: "meta")
        envelope["count"] = 2
        envelope["lastDataChange"] = currentFeedTimestamp()
        let mismatched = try JSONSerialization.data(withJSONObject: envelope)

        XCTAssertThrowsError(try JSONDecoder().decode(OpportunityListResponse.self, from: mismatched)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("A mismatched declared count must be rejected as corrupt data, got \(error).")
            }
        }
    }

    func testFreshEmptyFeedIsRejectedInsteadOfReplacingAUsableSnapshot() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let feedURL = URL(string: "https://example.com/opportunities.json")!
        let client = APIClient(feedURL: feedURL, session: makeURLSessionForStub())
        let payload = """
        {"count":0,"lastDataChange":"\(currentFeedTimestamp())","opportunities":[]}
        """.data(using: .utf8)!
        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)

        do {
            _ = try await client.opportunityFeed()
            XCTFail("A fresh but empty public feed must not replace a usable local snapshot.")
        } catch {
            XCTAssertEqual(URLProtocolStub.requestCount, 1)
        }
    }

    func testOpportunityDecodesTranslatedDynamicFields() throws {
        let json = """
        {
          "opportunities": [{
            "id": "translated-1",
            "title": "Robotics Club",
            "organization": "Public Library",
            "description": "Build robots.",
            "summary": "Build robots.",
            "category": "Coding & Robotics",
            "city": "Toronto",
            "region": "Toronto",
            "ageMin": 12,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com",
            "status": "active",
            "tags": ["robotics"],
            "translations": {
              "es": {
                "title": "Club de robótica",
                "provider": "Biblioteca pública",
                "description": "Construye robots.",
                "summary": "Construye robots.",
                "category": "Programación y robótica",
                "city": "Toronto",
                "region": "Toronto",
                "cost": "Gratis",
                "tags": ["robótica"]
              },
              "zh-Hans": {
                "title": "机器人俱乐部"
              }
            }
          }]
        }
        """.data(using: .utf8)!

        let opportunity = try XCTUnwrap(JSONDecoder().decode(OpportunityListResponse.self, from: json).data.first)

        XCTAssertEqual(opportunity.localizedTitle(language: .es), "Club de robótica")
        XCTAssertEqual(opportunity.localizedOrganization(language: .es), "Biblioteca pública")
        XCTAssertEqual(opportunity.localizedSummary(language: .es), "Construye robots.")
        XCTAssertEqual(opportunity.localizedCategory(language: .es), "Programación y robótica")
        XCTAssertEqual(opportunity.localizedCost(language: .es), "Gratis")
        XCTAssertEqual(opportunity.localizedTags(language: .es), ["robótica"])
        XCTAssertEqual(opportunity.localizedTitle(language: .zh), "机器人俱乐部")
        XCTAssertEqual(opportunity.localizedTitle(language: .fr), "Robotics Club")
    }

    func testAppTextLoadsLaunchLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 18)
        XCTAssertEqual(AppText.shared.string("browse", language: .ko), "둘러보기")
        XCTAssertEqual(AppText.shared.string("settings", language: .bn), "সেটিংস")
        XCTAssertEqual(AppText.shared.string("filters", language: .hu), "Szűrők")
        XCTAssertEqual(AppText.shared.string("openDetailsHint", language: .es), "Abre los detalles de la oportunidad.")
    }

    func testMissionClaimMatchesExactRightsClearedBundledInventoryScope() throws {
        let catalogURL = try XCTUnwrap(
            AppResources.url(forResource: "app_strings", withExtension: "json")
        )
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let english = try XCTUnwrap(catalog["en"] as? [String: String])
        let mission = try XCTUnwrap(english["mission"])

        XCTAssertEqual(
            mission,
            "Find free STEM programs and library events for children, families and adults in Toronto and Markham."
        )

        let feedURL = try XCTUnwrap(
            AppResources.url(forResource: "opportunities", withExtension: "json")
        )
        let feed = try JSONDecoder().decode(
            OpportunityListResponse.self,
            from: Data(contentsOf: feedURL)
        )
        let feedUpdated = try XCTUnwrap(feed.meta?.lastUpdated)
        let feedDate = try XCTUnwrap(FeedFreshness.date(from: feedUpdated))
        let exactCities: Set<String> = ["Toronto", "Markham"]
        let exactLibrarySources: Set<String> = [
            "Markham Public Library\u{001F}markham.bibliocommons.com",
            "Toronto Public Library\u{001F}tpl.bibliocommons.com"
        ]
        let observedLibrarySources = Set(feed.data.compactMap { opportunity -> String? in
            guard let host = URL(string: opportunity.sourceUrl)?.host?.lowercased() else {
                return nil
            }
            return "\(opportunity.organization)\u{001F}\(host)"
        })

        // These three exact branches are listed by Markham Public Library:
        // https://markhampubliclibrary.ca/locations/TV/ (10 Colborne Street)
        // https://markhampubliclibrary.ca/locations/TC/ (7755 Bayview Avenue)
        // https://markhampubliclibrary.ca/locations/UL/ (15 Library Lane)
        // Retain their district labels while checking municipal mission scope.
        let markhamDistrictBranches: [String: Set<String>] = [
            "Thornhill": ["Thornhill Comm. Ctr. Branch, 7755 Bayview Avenue, Thornhill, Ontario, L3T 4P1", "Thornhill Village Branch, 10 Colborne Street, Thornhill, Ontario, L3T 1Z6"],
            "Unionville": ["Unionville Branch, 15 Library Lane, Unionville, Ontario, L3R 5C4"]
        ]
        let municipalities = feed.data.map { opportunity -> String in
            guard let addresses = markhamDistrictBranches[opportunity.city] else { return opportunity.city }
            XCTAssertEqual(opportunity.organization, "Markham Public Library")
            XCTAssertEqual(URL(string: opportunity.sourceUrl)?.host, "markham.bibliocommons.com")
            XCTAssertTrue(addresses.contains(opportunity.address ?? ""))
            return "Markham"
        }
        XCTAssertEqual(Set(feed.data.map(\.city)), ["Toronto", "Markham", "Thornhill", "Unionville"])
        XCTAssertEqual(Set(municipalities), exactCities)
        XCTAssertEqual(observedLibrarySources, exactLibrarySources)
        XCTAssertEqual(feed.meta?.activeCount, feed.data.count)
        XCTAssertTrue(feed.hasReleaseReadyContentRights(now: feedDate))
        XCTAssertTrue(feed.data.allSatisfy(\.isExplicitlyFree))
        XCTAssertTrue(feed.data.allSatisfy {
            $0.registrationUrl == $0.sourceUrl && !$0.volunteerHoursEligible && !$0.coopEligible
        })
        for city in exactCities {
            XCTAssertTrue(mission.contains(city), "The mission must name the published city \(city).")
        }

        let unavailableClaims = [
            "across the gta", "gta-wide", "volunteer", "co-op", "shsm", "mentorship", "scholarship"
        ]
        for claim in unavailableClaims {
            XCTAssertFalse(
                mission.lowercased().contains(claim),
                "The English mission must not promise unavailable \(claim) inventory."
            )
        }
    }

    func testEnglishBrowseClaimsDoNotPromiseUniversalEligibilityOrGTAWideCoverage() throws {
        let catalogURL = try XCTUnwrap(
            AppResources.url(forResource: "app_strings", withExtension: "json")
        )
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let english = try XCTUnwrap(catalog["en"] as? [String: String])
        let freeOnly = try XCTUnwrap(english["freeOnly"])
        let freeShort = try XCTUnwrap(english["freeShort"])
        let allRegions = try XCTUnwrap(english["allGta"])
        let availableRegions = try XCTUnwrap(english["acrossGTA"])

        XCTAssertEqual(freeOnly, "Every listing is verified free of charge.")
        XCTAssertTrue(freeOnly.lowercased().contains("verified"))
        XCTAssertTrue(freeOnly.lowercased().contains("free of charge"))
        XCTAssertFalse(freeOnly.lowercased().contains("for everyone"))

        XCTAssertEqual(freeShort, "Verified free")
        XCTAssertFalse(freeShort.lowercased().contains("everyone"))
        XCTAssertEqual(allRegions, "All regions")
        XCTAssertEqual(availableRegions, "across available regions")
        XCTAssertFalse(allRegions.lowercased().contains("gta"))
        XCTAssertFalse(availableRegions.lowercased().contains("gta"))
    }

    func testInterfaceCatalogDoesNotPromiseUnimplementedCalendarAction() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let english = try XCTUnwrap(catalog["en"] as? [String: String])

        XCTAssertNil(english["calendar"])
    }

    func testPreferredLanguageUsesStoredLanguageBeforeSystemLanguage() {
        let defaults = makeIsolatedDefaults()
        defaults.set("es", forKey: AppLanguage.preferredLanguageDefaultsKey)

        XCTAssertEqual(
            AppLanguage.preferred(defaults: defaults, preferredLanguages: ["ar-CA", "fr-CA"]),
            .es
        )
    }

    func testPreferredLanguageFallsBackToSystemLanguageOnFirstLaunch() {
        let defaults = makeIsolatedDefaults()

        XCTAssertEqual(
            AppLanguage.preferred(defaults: defaults, preferredLanguages: ["de-CA", "ar-CA", "fr-CA"]),
            .ar
        )
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["pt-BR"]), .pt)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["fil-PH"]), .tl)
    }

    func testTraditionalChineseDoesNotSilentlySelectSimplifiedMandarin() {
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["zh-Hans-CN"]), .zh)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["zh-Hant-TW", "en-CA"]), .en)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["zh-TW", "fr-CA"]), .fr)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["zh-TW-u-nu-hanidec", "en-CA"]), .en)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["yue-Hant-HK"]), .yue)
        XCTAssertEqual(AppLanguage.preferredSystemLanguage(from: ["zh-yue-Hant"]), .yue)
        XCTAssertEqual(AppLanguage.normalized("zh-Hant-TW"), .en)
        XCTAssertNil(AppLanguage.supportedLanguage(for: "zh-Hant-TW"))
        XCTAssertNil(AppLanguage.supportedLanguage(for: "zh-TW-u-nu-hanidec"))
        XCTAssertEqual(AppLanguage.supportedLanguage(for: "zh-yue-Hant"), .yue)
        XCTAssertEqual(AppText.shared.languageName(.zh), "简体中文 - Mandarin (Simplified)")
        XCTAssertEqual(AppText.shared.languageName(.es), "Español - Spanish")
        XCTAssertEqual(AppText.shared.languageName(.pt), "Português - Portuguese")
    }

    func testUnsupportedTranslationKeyNeverAliasesToEnglish() {
        let opportunity = opportunity(
            id: "traditional-key",
            title: "English base title",
            translations: [
                "zh-Hant-TW": OpportunityTranslation(title: "繁體中文標題")
            ]
        )

        XCTAssertEqual(opportunity.localizedTitle(language: .en), "English base title")
        XCTAssertEqual(opportunity.translations["zh-Hant-TW"]?.title, "繁體中文標題")
        XCTAssertNil(opportunity.translations[AppLanguage.en.rawValue])
    }

    func testResultCountAnnouncementsUseLocalizedSingularAndPluralTemplates() {
        XCTAssertEqual(OpportunityResultCountText.string(1, language: .en), "1 result")
        XCTAssertEqual(OpportunityResultCountText.string(2, language: .en), "2 results")
        XCTAssertEqual(OpportunityResultCountText.string(1, language: .fr), "1 résultat")
        XCTAssertTrue(OpportunityResultCountText.string(12, language: .ja).hasSuffix("件"))
    }

    func testModelContainerResolutionUsesPersistentContainerWhenAvailable() throws {
        let persistent = try makeAppTestModelContainer()
        var fallbackWasRequested = false

        let resolution = try AppModelContainerResolution.resolve(
            persistent: { persistent },
            ephemeralFallback: {
                fallbackWasRequested = true
                return try makeAppTestModelContainer()
            }
        )

        XCTAssertTrue(resolution.container === persistent)
        XCTAssertFalse(resolution.usesEphemeralFallback)
        XCTAssertTrue(resolution.storageAccess.allowsPersistentChanges)
        XCTAssertNil(resolution.persistentInitializationErrorDescription)
        XCTAssertFalse(fallbackWasRequested)
    }

    func testModelContainerResolutionPreservesLaunchWithEphemeralFallback() throws {
        struct PersistentStoreFailure: Error {}
        let fallback = try makeAppTestModelContainer()

        let resolution = try AppModelContainerResolution.resolve(
            persistent: { throw PersistentStoreFailure() },
            ephemeralFallback: { fallback }
        )

        XCTAssertTrue(resolution.container === fallback)
        XCTAssertTrue(resolution.usesEphemeralFallback)
        XCTAssertFalse(resolution.storageAccess.allowsPersistentChanges)
        XCTAssertNotNil(resolution.persistentInitializationErrorDescription)
    }

    func testReadOnlyRecoveryModeBlocksPersistentUIAndWatchPublishing() throws {
        let repoRoot = testRepositoryRoot
        let app = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift"))
        let content = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))
        let details = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/OpportunityDetailView.swift"))
        let models = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/Models.swift"))
        let saved = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SavedView.swift"))
        let settings = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))

        XCTAssertTrue(app.contains(".environment(\\.appStorageAccess"))
        XCTAssertTrue(app.contains("storageAccess.allowsPersistentChanges"))
        XCTAssertTrue(content.contains("storageAccess.allowsPersistentChanges ? modelContext : nil"))
        XCTAssertTrue(content.contains("StorageRecoveryBanner()"))
        XCTAssertTrue(content.contains(".foregroundStyle(Brand.ink)"))
        XCTAssertTrue(content.contains(".background(Brand.cream)"))
        XCTAssertTrue(details.contains(".disabled(!storageAccess.allowsPersistentChanges)"))
        XCTAssertTrue(models.contains("guard isConfigured else { return }"))
        XCTAssertTrue(saved.contains("if !storageAccess.allowsPersistentChanges"))
        XCTAssertTrue(settings.contains("guard storageAccess.allowsPersistentChanges else"))

        func relativeLuminance(_ color: [Double]) -> Double {
            let linear = color.map { channel in
                channel <= 0.04045
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            return (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
        }
        let inkLuminance = relativeLuminance([0.05, 0.09, 0.11])
        let creamLuminance = relativeLuminance([0.98, 0.97, 0.92])
        XCTAssertGreaterThanOrEqual((creamLuminance + 0.05) / (inkLuminance + 0.05), 4.5)
    }

    @MainActor
    func testSessionPersistsSystemLanguageOnFirstLaunch() {
        let defaults = makeIsolatedDefaults()
        let session = SessionStore(defaults: defaults, preferredLanguages: ["fr-CA"])

        XCTAssertEqual(session.preferredLanguageCode, AppLanguage.fr.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.preferredLanguageDefaultsKey), AppLanguage.fr.rawValue)
        XCTAssertEqual(session.displayName, AppText.shared.string("guest", language: .fr))
    }

    @MainActor
    func testSessionPersistsAndClearsAnOnDeviceProfile() {
        let defaults = makeIsolatedDefaults()
        let session = SessionStore(defaults: defaults, preferredLanguages: ["en-CA"])

        session.saveLocalProfile(named: "  Avery  ")

        XCTAssertTrue(session.hasLocalProfile)
        XCTAssertEqual(session.displayName, "Avery")

        session.preferredLanguageCode = AppLanguage.fr.rawValue
        XCTAssertEqual(session.displayName, "Avery", "Changing language must not erase the local profile name.")

        let restoredSession = SessionStore(defaults: defaults, preferredLanguages: ["en-CA"])
        XCTAssertTrue(restoredSession.hasLocalProfile)
        XCTAssertEqual(restoredSession.displayName, "Avery")

        restoredSession.clearLocalProfile()
        XCTAssertFalse(restoredSession.hasLocalProfile)
        XCTAssertEqual(restoredSession.displayName, restoredSession.text("guest"))
    }

    func testExternalOpportunityURLAllowsOnlyWebLinksAndUpgradesHTTP() {
        XCTAssertEqual(ExternalOpportunityURL.make(from: "http://example.com/register?session=1")?.absoluteString, "https://example.com/register?session=1")
        XCTAssertEqual(ExternalOpportunityURL.make(from: " https://example.com/program ")?.absoluteString, "https://example.com/program")
        XCTAssertNil(ExternalOpportunityURL.make(from: "javascript:alert(1)"))
        XCTAssertNil(ExternalOpportunityURL.make(from: "file:///private/data"))
        XCTAssertNil(ExternalOpportunityURL.make(from: ""))
    }

    func testWatchSourceUsesSavedEventSyncAndHonestTimestamps() throws {
        let repoRoot = testRepositoryRoot
        let watchSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))

        XCTAssertTrue(watchSource.contains("savedEventsPayload"))
        XCTAssertTrue(watchSource.contains("requestSavedEvents"))
        XCTAssertTrue(watchSource.contains("watch-saved-events-v1"))
        XCTAssertTrue(watchSource.contains("session.receivedApplicationContext"))
        XCTAssertTrue(watchSource.contains("lastSyncedAt = envelope.syncedAt"))
        XCTAssertTrue(watchSource.contains("Still showing the latest events saved on this watch."))
        XCTAssertTrue(watchSource.contains("let shouldRequestSync = self.isSyncing"))
        XCTAssertTrue(watchSource.contains("error == nil, shouldRequestSync"))
        XCTAssertTrue(watchSource.contains("let archiveBoundary: Date?"))
        XCTAssertTrue(watchSource.contains("if archived == true { return true }"))
        XCTAssertTrue(
            watchSource.contains("TimeZone(identifier: \"America/Toronto\")"),
            "Date-only GTA events must retain their declared calendar day on Watch."
        )
        XCTAssertFalse(watchSource.contains("expiryDate(from: startDate)"))
        XCTAssertFalse(watchSource.contains("URLSession"), "The Watch companion must use the paired iPhone's saved-event sync rather than its own public network feed.")
    }

    func testWatchControlsMeetTargetContrastAndReducedMotionRequirements() throws {
        let repoRoot = testRepositoryRoot
        let watchSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))

        XCTAssertTrue(watchSource.contains("frame(minWidth: 44, minHeight: 44)"))
        XCTAssertEqual(
            watchSource.components(separatedBy: ".watchAccessibleControl()").count - 1,
            9,
            "Every explicit Watch button, link, and navigation link should use the shared 44-point target."
        )
        XCTAssertTrue(watchSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(watchSource.contains("if store.isSyncing, !reduceMotion"))
        XCTAssertFalse(watchSource.contains("repeatForever"))
        XCTAssertTrue(watchSource.contains("Text(localization.text(.savedEvents))\n                    .font(.title3.weight(.black))\n                    .lineLimit(2)"))

        let cardStart = try XCTUnwrap(watchSource.range(of: "private struct WatchNextEventCard"))
        let rowStart = try XCTUnwrap(
            watchSource.range(of: "private struct WatchEventRow", range: cardStart.lowerBound..<watchSource.endIndex)
        )
        let cardSource = String(watchSource[cardStart.lowerBound..<rowStart.lowerBound])
        XCTAssertFalse(cardSource.contains(".foregroundStyle(.white"))
        XCTAssertEqual(cardSource.components(separatedBy: ".foregroundStyle(WatchTheme.ink)").count - 1, 3)
        XCTAssertTrue(cardSource.contains("colors: [WatchTheme.coral, WatchTheme.orange]"))

        func relativeLuminance(_ color: [Double]) -> Double {
            let linear = color.map { channel in
                channel <= 0.04045
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }
            return (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2])
        }

        func contrastRatio(_ first: [Double], _ second: [Double]) -> Double {
            let firstLuminance = relativeLuminance(first)
            let secondLuminance = relativeLuminance(second)
            let lighter = max(firstLuminance, secondLuminance)
            let darker = min(firstLuminance, secondLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        let ink = [0.05, 0.07, 0.08]
        XCTAssertGreaterThanOrEqual(contrastRatio(ink, [0.95, 0.34, 0.22]), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(ink, [1.00, 0.49, 0.19]), 4.5)
    }

    func testWatchSavedTransferCarriesTheIPhoneArchivePolicy() {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let current = opportunity(
            id: "watch-current",
            title: "Watch Current",
            startDate: formatter.string(from: now.addingTimeInterval(-86_400)),
            deadline: formatter.string(from: now.addingTimeInterval(86_400))
        )
        let currentTransfer = WatchSavedEventTransfer(opportunity: current, savedAt: now, language: .en)

        XCTAssertFalse(LocalOpportunitySnapshot.isArchived(current, on: now))
        XCTAssertFalse(currentTransfer.archived)
        XCTAssertEqual(currentTransfer.archiveBoundary, LocalOpportunitySnapshot.archiveBoundary(for: current))

        let withheld = opportunity(
            id: "watch-withheld",
            title: "Watch Withheld",
            startDate: formatter.string(from: now.addingTimeInterval(86_400)),
            status: "needs_review"
        )
        let withheldTransfer = WatchSavedEventTransfer(opportunity: withheld, savedAt: now, language: .en)

        XCTAssertTrue(LocalOpportunitySnapshot.isArchived(withheld, on: now))
        XCTAssertTrue(withheldTransfer.archived)
        XCTAssertLessThan(withheldTransfer.archiveBoundary ?? .distantFuture, now)
    }

    func testWatchPayloadBuilderCapsBothEventCountAndEncodedBytes() throws {
        let normalEvents = (0..<60).map { index in
            WatchSavedEventTransfer(
                opportunity: opportunity(id: "normal-\(index)", title: "Saved STEM Event \(index)"),
                savedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let normalPayload = try XCTUnwrap(
            WatchSavedEventsPayloadBuilder.makePayload(
                totalSavedCount: normalEvents.count,
                prioritizedEvents: normalEvents
            )
        )
        let normalEnvelope = try JSONDecoder().decode(WatchSavedEventsTransfer.self, from: normalPayload)
        XCTAssertEqual(normalEnvelope.totalSavedCount, 60)
        XCTAssertEqual(normalEnvelope.events.count, WatchSavedEventsPayloadBuilder.maximumTransferredEvents)
        XCTAssertLessThanOrEqual(normalPayload.count, WatchSavedEventsPayloadBuilder.maximumEncodedPayloadBytes)

        let multibyteText = String(repeating: "界🧪", count: 500)
        let oversizedEvents = (0..<48).map { index in
            WatchSavedEventTransfer(
                opportunity: opportunity(
                    id: "large-\(index)-\(multibyteText)",
                    title: multibyteText,
                    organization: multibyteText,
                    description: multibyteText,
                    summary: multibyteText,
                    category: multibyteText,
                    city: multibyteText,
                    region: multibyteText
                ),
                savedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let boundedPayload = try XCTUnwrap(
            WatchSavedEventsPayloadBuilder.makePayload(
                totalSavedCount: oversizedEvents.count,
                prioritizedEvents: oversizedEvents
            )
        )
        let boundedEnvelope = try JSONDecoder().decode(WatchSavedEventsTransfer.self, from: boundedPayload)

        XCTAssertEqual(boundedEnvelope.totalSavedCount, 48)
        XCTAssertGreaterThan(boundedEnvelope.events.count, 0)
        XCTAssertLessThan(boundedEnvelope.events.count, 48)
        XCTAssertTrue(boundedEnvelope.events.allSatisfy { $0.id.count <= 200 })
        XCTAssertEqual(Set(boundedEnvelope.events.map(\.id)).count, boundedEnvelope.events.count)
        XCTAssertLessThanOrEqual(boundedPayload.count, WatchSavedEventsPayloadBuilder.maximumEncodedPayloadBytes)
    }

    func testWatchPayloadCarriesPreferredLanguageAndDecodesLegacyEnvelope() throws {
        let payload = try XCTUnwrap(
            WatchSavedEventsPayloadBuilder.makePayload(
                totalSavedCount: 0,
                prioritizedEvents: [],
                syncedAt: Date(timeIntervalSince1970: 123),
                preferredLanguageCode: AppLanguage.fr.rawValue
            )
        )
        let current = try JSONDecoder().decode(WatchSavedEventsTransfer.self, from: payload)
        XCTAssertEqual(current.preferredLanguageCode, AppLanguage.fr.rawValue)

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "preferredLanguageCode")
        let legacyPayload = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(WatchSavedEventsTransfer.self, from: legacyPayload)

        XCTAssertNil(legacy.preferredLanguageCode)
        XCTAssertEqual(legacy.schemaVersion, WatchSavedEventsTransfer.currentSchemaVersion)
        XCTAssertEqual(legacy.totalSavedCount, 0)
    }

    func testWatchLocalizationCatalogCoversEveryKeyAndLanguageAndIsBundled() throws {
        let repoRoot = testRepositoryRoot
        let watchSource = try String(
            contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift")
        )
        let catalogData = try Data(
            contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/WatchStrings.json")
        )
        let catalog = try JSONDecoder().decode([String: [String: String]].self, from: catalogData)
        let expectedLanguages: Set<String> = [
            "en", "fr", "zh", "yue", "pa", "ur", "ta", "tl", "es",
            "ar", "fa", "hi", "pt", "gu", "bn", "ja", "ko", "hu"
        ]
        XCTAssertEqual(Set(catalog.keys), expectedLanguages)

        let keyPattern = try NSRegularExpression(pattern: #"=\s*\"(watch\.[A-Za-z0-9]+)\""#)
        let sourceRange = NSRange(watchSource.startIndex..<watchSource.endIndex, in: watchSource)
        let watchKeys: Set<String> = Set(keyPattern.matches(in: watchSource, range: sourceRange).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: watchSource) else { return nil }
            return String(watchSource[range])
        })
        let english = try XCTUnwrap(catalog["en"])
        XCTAssertEqual(Set(english.keys), watchKeys)
        let cantoneseResolution = try XCTUnwrap(watchSource.range(of: "normalized.hasPrefix(\"zh-yue-\")"))
        let traditionalMandarinGuard = try XCTUnwrap(watchSource.range(of: "if normalized.hasPrefix(\"zh-\")"))
        XCTAssertLessThan(cantoneseResolution.lowerBound, traditionalMandarinGuard.lowerBound)

        let tokenPattern = try NSRegularExpression(pattern: #"\{[A-Za-z0-9]+\}"#)
        func tokens(in value: String) -> Set<String> {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return Set(tokenPattern.matches(in: value, range: range).compactMap { match -> String? in
                guard let tokenRange = Range(match.range, in: value) else { return nil }
                return String(value[tokenRange])
            })
        }

        for language in expectedLanguages.sorted() {
            let strings = try XCTUnwrap(catalog[language], "Missing Watch catalog for \(language)")
            XCTAssertEqual(Set(strings.keys), watchKeys, "Watch key mismatch for \(language)")
            for key in watchKeys {
                let value = try XCTUnwrap(strings[key])
                XCTAssertFalse(value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(tokens(in: value), tokens(in: try XCTUnwrap(english[key])), "Token mismatch for \(language).\(key)")
            }
        }

        let project = try String(
            contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM.xcodeproj/project.pbxproj")
        )
        let projectDefinition = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"))
        XCTAssertTrue(project.contains("WatchStrings.json in Resources"))
        XCTAssertTrue(projectDefinition.contains("- GTAFreeSTEMWatch/WatchStrings.json"))
    }

    func testCurrentSourceContractFixturesAlwaysRestageBeforeTests() throws {
        let repoRoot = testRepositoryRoot
        let projectDefinition = try String(
            contentsOf: repoRoot.appendingPathComponent("project.yml")
        )
        let generatedProject = try String(
            contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM.xcodeproj/project.pbxproj")
        )

        XCTAssertTrue(projectDefinition.contains("basedOnDependencyAnalysis: false"))
        XCTAssertTrue(generatedProject.contains("alwaysOutOfDate = 1;"))
    }

    func testReleaseSourceContainsNoDormantAccountOrLegacyWatchFeedState() throws {
        let repoRoot = testRepositoryRoot
        let sessionContents = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SessionStore.swift"))
        let storeContents = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/OpportunityStore.swift"))
        let watchContents = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))
        let modelContents = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/Models.swift"))

        XCTAssertFalse(sessionContents.contains("apiToken"))
        XCTAssertFalse(sessionContents.contains("authMessage"))
        XCTAssertFalse(storeContents.contains("railsAPI"))
        XCTAssertTrue(watchContents.contains("WatchExternalURL.make"))
        XCTAssertTrue(watchContents.contains("components.scheme = \"https\""))
        XCTAssertTrue(modelContents.contains("maximumTransferredEvents = 48"))
        XCTAssertTrue(modelContents.contains("maximumEncodedPayloadBytes = 48 * 1_024"))
        XCTAssertTrue(modelContents.contains("lastPublishErrorDescription = error.localizedDescription"))
        XCTAssertTrue(modelContents.contains("updateApplicationContext"))
        XCTAssertTrue(modelContents.contains("preferredLanguageKey = \"preferredLanguageCode\""))
        XCTAssertTrue(modelContents.contains("preferredLanguageCode: language.rawValue"))
        XCTAssertTrue(sessionContents.contains("preferredLanguageDidChange(to: normalized)"))
        XCTAssertFalse(watchContents.contains("URLSession"))
    }

    @MainActor
    func testCategoryNamesUseLocalizedStringsWhenAvailable() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
        }

        let session = SessionStore()
        session.preferredLanguageCode = AppLanguage.es.rawValue

        XCTAssertEqual(
            session.categoryName("Coding & Robotics"),
            AppText.shared.string("categoryCodingAndRobotics", language: .es)
        )
        XCTAssertEqual(session.categoryName("Mystery Category"), "Mystery Category")
    }

    @MainActor
    func testSessionUsesTranslatedOpportunityFieldsWhenAvailable() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
        }

        let session = SessionStore()
        session.preferredLanguageCode = AppLanguage.es.rawValue
        let translated = opportunity(
            id: "session-translated",
            title: "Robotics Club",
            organization: "Public Library",
            description: "Build robots.",
            summary: "Build robots.",
            translations: [
                "es": OpportunityTranslation(
                    title: "Club de robótica",
                    organization: "Biblioteca pública",
                    summary: "Construye robots.",
                    category: "Programación y robótica",
                    city: "Toronto",
                    region: "Ontario",
                    cost: "Gratis"
                )
            ]
        )

        XCTAssertEqual(session.title(for: translated), "Club de robótica")
        XCTAssertEqual(session.organization(for: translated), "Biblioteca pública")
        XCTAssertEqual(session.summary(for: translated), "Construye robots.")
        XCTAssertEqual(session.categoryName(for: translated), "Programación y robótica")
        XCTAssertEqual(session.city(for: translated), "Toronto")
        XCTAssertEqual(session.region(for: translated), "Ontario")
        XCTAssertEqual(session.cost(for: translated), "Gratis")
    }

    @MainActor
    func testSessionSummaryFallsBackToEnglishOnceWhenTranslationIsMissing() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
        }

        let session = SessionStore()
        session.preferredLanguageCode = AppLanguage.es.rawValue
        let englishOnly = opportunity(
            id: "session-fallback",
            title: "Robotics Club",
            organization: "Public Library",
            description: "Build robots.",
            summary: "Build robots."
        )

        let summary = session.summary(for: englishOnly)

        XCTAssertTrue(summary.contains("Build robots."))
        XCTAssertEqual(summary.components(separatedBy: "Build robots.").count - 1, 1)
        XCTAssertFalse(summary.contains(AppText.shared.string("summaryTemplate", language: .es)))
    }

    func testEveryLaunchLanguageHasEveryEnglishKey() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let english = try XCTUnwrap(json["en"] as? [String: String])

        for language in AppLanguage.allCases {
            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for key in english.keys {
                XCTAssertNotNil(strings[key], "\(language.rawValue) is missing \(key)")
            }
        }
    }

    func testEveryLaunchLanguageHasMetadataAndNonEmptyStrings() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let meta = try XCTUnwrap(json["languageMeta"] as? [String: [String: String]])
        let english = try XCTUnwrap(json["en"] as? [String: String])

        for language in AppLanguage.allCases {
            let info = try XCTUnwrap(meta[language.rawValue], "\(language.rawValue) is missing language metadata")
            XCTAssertFalse((info["label"] ?? "").isEmpty, "\(language.rawValue) is missing a language label")
            XCTAssertFalse((info["native"] ?? "").isEmpty, "\(language.rawValue) is missing a native language label")
            XCTAssertEqual(info["dir"], [.ar, .fa, .ur].contains(language) ? "rtl" : "ltr")

            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for key in english.keys {
                let value = try XCTUnwrap(strings[key], "\(language.rawValue) is missing \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language.rawValue).\(key) is empty")
            }
        }
    }

    func testReleaseStringsDoNotExposeBackendSetupInstructions() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let forbiddenPhrases = ["connect rails", "oauth callback", "before testflight"]

        for language in AppLanguage.allCases {
            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for (key, value) in strings {
                let lowercased = value.lowercased()
                for phrase in forbiddenPhrases {
                    XCTAssertFalse(
                        lowercased.contains(phrase),
                        "\(language.rawValue).\(key) exposes developer setup copy: \(value)"
                    )
                }
            }
        }
    }

    func testSettingsDoesNotExposeAppleSignInWithoutTokenExchange() throws {
        let repoRoot = testRepositoryRoot
        let settingsView = repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift")
        let sessionStore = repoRoot.appendingPathComponent("GTAFreeSTEM/SessionStore.swift")

        XCTAssertFalse(
            try String(contentsOf: settingsView).contains("SignInWithAppleButton"),
            "Do not show Sign in with Apple until iOS exchanges Apple credentials for a backend API token."
        )
        XCTAssertFalse(
            try String(contentsOf: sessionStore).contains("ASAuthorization"),
            "SessionStore should not handle Apple authorization without a backend token exchange."
        )
    }

    func testLegalAndSupportLinksUseDistinctProductionHTTPSPages() {
        let expected: [(URL, String)] = [
            (AppLegalLinks.privacyPolicy, "https://gta-free-stem.pages.dev/privacy/"),
            (AppLegalLinks.termsOfUse, "https://gta-free-stem.pages.dev/terms/"),
            (AppLegalLinks.support, "https://gta-free-stem.pages.dev/support/")
        ]

        XCTAssertEqual(Set(expected.map(\.0)).count, expected.count)
        for (url, absoluteString) in expected {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "gta-free-stem.pages.dev")
            XCTAssertEqual(url.absoluteString, absoluteString)
        }
    }

    func testSupportViewDoesNotCollectOrPersistSubmissionPersonalData() throws {
        let repoRoot = testRepositoryRoot
        let submitView = repoRoot.appendingPathComponent("GTAFreeSTEM/SubmitView.swift")
        let contents = try String(contentsOf: submitView)

        XCTAssertFalse(contents.contains("TextField("), "Release support view should not collect name, email, feedback, or submission text while App Privacy says no collected user data.")
        XCTAssertFalse(contents.contains("previewSubmissions"), "Release support view must not store personal submission drafts in UserDefaults.")
        XCTAssertFalse(contents.contains("UserDefaults.standard.set"), "Release support view must not persist personal support data locally.")
        XCTAssertFalse(contents.contains("sendFeedback("), "Release support view should not transmit feedback until backend privacy handling is live.")
        XCTAssertFalse(contents.contains("submitMissingOpportunity("), "Release support view should not transmit missing-opportunity submissions until backend privacy handling is live.")
    }

    func testReleaseAPIClientContainsOnlyReadOnlyFeedRequests() throws {
        let repoRoot = testRepositoryRoot
        let apiClient = repoRoot.appendingPathComponent("GTAFreeSTEM/APIClient.swift")
        let contents = try String(contentsOf: apiClient)

        XCTAssertFalse(contents.contains("session.data(for:"), "The privacy-safe release client must not make mutating URLSession requests.")
        XCTAssertFalse(contents.contains("httpMethod"), "The privacy-safe release client must not set POST, PUT, PATCH, or DELETE request methods.")
        XCTAssertFalse(contents.contains("onrender.com"), "The retired account backend must not be compiled into the release client.")
        XCTAssertFalse(contents.contains("saved_opportunities"))
        XCTAssertFalse(contents.contains("missing_opportunity_submissions"))
        XCTAssertFalse(contents.contains("hunt_refresh"))
    }

    func testPermissionCopyIsLocalizedForLaunchLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertNotNil(
                AppResources.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language.localeIdentifier
                ),
                "\(language.rawValue) is missing localized permission copy"
            )
        }
    }

    func testPrivacyManifestDeclaresLocalStorageAndConservativeFeedProviderDisclosure() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((plist["NSPrivacyTrackingDomains"] as? [String] ?? []).isEmpty)
        let collectedDataTypes = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(collectedDataTypes.count, 2)
        for type in [
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData"
        ] {
            let declaration = try XCTUnwrap(collectedDataTypes.first {
                $0["NSPrivacyCollectedDataType"] as? String == type
            })
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(
                Set(declaration["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []),
                [
                    "NSPrivacyCollectedDataTypePurposeAnalytics",
                    "NSPrivacyCollectedDataTypePurposeAppFunctionality"
                ]
            )
        }

        let accessedAPITypes = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaultsEntry = accessedAPITypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try XCTUnwrap(userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"))
    }

    func testWatchPrivacyManifestDeclaresAppOnlyUserDefaultsAccess() throws {
        let repoRoot = testRepositoryRoot
        let url = repoRoot.appendingPathComponent("GTAFreeSTEMWatch/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((plist["NSPrivacyTrackingDomains"] as? [String] ?? []).isEmpty)
        XCTAssertTrue((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)

        let accessedAPITypes = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaultsEntry = accessedAPITypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try XCTUnwrap(userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"))
    }

    func testMacCatalystReleaseConfigurationIsSandboxed() throws {
        let repoRoot = testRepositoryRoot
        let project = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"))
        let generatedProject = try String(
            contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM.xcodeproj/project.pbxproj")
        )
        let entitlementsURL = repoRoot.appendingPathComponent("GTAFreeSTEM/MacCatalyst.entitlements")
        let infoURL = repoRoot.appendingPathComponent("GTAFreeSTEM/MacCatalyst-Info.plist")

        XCTAssertTrue(project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\": GTAFreeSTEM/MacCatalyst.entitlements"))
        XCTAssertTrue(project.contains("\"ENABLE_APP_SANDBOX[sdk=macosx*]\": \"YES\""))
        XCTAssertTrue(project.contains("\"ENABLE_HARDENED_RUNTIME[sdk=macosx*]\": \"YES\""))
        for signingConfiguration in [project, generatedProject] {
            XCTAssertFalse(
                signingConfiguration.contains("CODE_SIGN_IDENTITY"),
                "Automatic signing must choose the development identity for archives and the distribution identity at export time."
            )
        }

        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.personal-information.location"] as? Bool, true)

        let infoData = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(info["LSApplicationCategoryType"] as? String, "public.app-category.education")
        XCTAssertEqual(info["NSHumanReadableCopyright"] as? String, "© 2026 Rupayon Haldar")
    }

    func testWatchCompanionShowsSavedAndArchivedEvents() throws {
        let repoRoot = testRepositoryRoot
        let watchApp = repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift")
        let contents = try String(contentsOf: watchApp)

        XCTAssertTrue(contents.contains("Saved events"))
        XCTAssertTrue(contents.contains("Event archive"))
        XCTAssertTrue(contents.contains("Your past saved events are still available in the archive."))
        XCTAssertTrue(contents.contains(".showingSavedEvents"))
        XCTAssertTrue(contents.contains("store.events.count"))
        XCTAssertTrue(contents.contains("store.totalSavedCount"))
        XCTAssertTrue(contents.contains("Open GTA FREE STEM on your iPhone to refresh saved events."))
    }

    func testReleaseNavigationAndSupportSurfacesPresentAsFinished() throws {
        let repoRoot = testRepositoryRoot
        let designSystem = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/DesignSystem.swift"))
        let contentView = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))
        let settingsView = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))
        let supportView = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SubmitView.swift"))

        XCTAssertTrue(designSystem.contains("static let compactName = \"GTA FREE STEM\""))
        XCTAssertTrue(contentView.contains(".navigationTitle(Brand.compactName)"))
        XCTAssertFalse(contentView.contains(".navigationTitle(session.text(\"brand\"))"))
        XCTAssertFalse(settingsView.contains("session.text(\"localSubmissionSaved\")"))
        XCTAssertTrue(settingsView.contains("Text(session.text(\"termsBody\"))"))
        XCTAssertFalse(settingsView.contains("StorySectionTitle(text: session.text(\"termsTitle\"), systemImage: \"doc.text.fill\")\n            Text(session.text(\"profileOnDevice\"))"))
        XCTAssertFalse(supportView.contains("session.text(\"localSubmissionSaved\")"))
        XCTAssertTrue(supportView.contains("session.text(\"supportHeading\")"))
        XCTAssertTrue(supportView.contains("AppLegalLinks.support"))
        XCTAssertTrue(supportView.contains("AppLegalLinks.privacyPolicy"))
        XCTAssertTrue(supportView.contains("AppLegalLinks.termsOfUse"))
    }

    func testLanguageNamesDoNotRepeatIdenticalNativeAndEnglishLabels() {
        XCTAssertEqual(AppText.shared.languageName(.en), "English")
        XCTAssertEqual(AppText.shared.languageName(.fr), "Français - French")
    }

    func testStorefrontCriticalCompactLayoutsAvoidClippedControls() throws {
        let repoRoot = testRepositoryRoot
        let browseView = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift"))
        let designSystem = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/DesignSystem.swift"))
        let watchView = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))

        XCTAssertTrue(browseView.contains("WrappingHStack("))
        XCTAssertTrue(browseView.contains("layoutDirection: layoutDirection"))
        XCTAssertTrue(browseView.contains(".minimumScaleFactor(0.80)"))
        XCTAssertTrue(designSystem.contains("struct WrappingHStack: Layout"))
        XCTAssertTrue(designSystem.contains("layoutDirection == .rightToLeft"))
        XCTAssertFalse(watchView.contains("WatchSectionHeading(title: \"NEXT UP\""))
        XCTAssertTrue(watchView.contains("else if store.upcomingEvents.count > 1"))
        XCTAssertTrue(watchView.contains("Text(event.category.uppercased(with: localization.locale))"))
        XCTAssertTrue(watchView.contains(".minimumScaleFactor(0.72)"))
        XCTAssertTrue(watchView.contains(".lineLimit(2)"))
        XCTAssertTrue(watchView.contains("$0.trimmingCharacters(in: .whitespacesAndNewlines)"))
    }

    func testCompactBrowseLayoutPrioritizesLiveResults() throws {
        let repoRoot = testRepositoryRoot
        let browseView = repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift")
        let contents = try String(contentsOf: browseView)

        XCTAssertTrue(contents.contains("horizontalSizeClass == .compact && displayMode == .list"))
        XCTAssertTrue(contents.contains("if prioritizesResultsOnCompactLayout {"))
        XCTAssertTrue(contents.contains("resultsContent\n                            huntPanel"))
    }

    func testAPIClientRejectsPlainHTTP() async throws {
        let client = APIClient(feedURL: URL(string: "http://example.com/opportunities.json")!)

        do {
            let _: OpportunityListResponse = try await client.opportunities(query: "", mode: .all, filters: OpportunityFilters())
            XCTFail("Plain HTTP should not be accepted by the app API client.")
        } catch APIError.insecureConnection {
            return
        } catch {
            XCTFail("Expected insecureConnection, got \(error)")
        }
    }

    func testMissingFullTranslationKeepsOriginalSourceTextSearchable() async throws {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defaults.set("fr", forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
            URLProtocolStub.reset()
        }

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let now = try bundledSnapshotTestNow()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let target = try XCTUnwrap(bundled.data.first)
        XCTAssertTrue(target.translations.isEmpty)
        let expectedDescription = target.description
        let bundleURL = try XCTUnwrap(AppResources.url(forResource: "opportunities", withExtension: "json"))
        var liveOnly = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: bundleURL)) as? [String: Any]
        )
        let bundledItems = try XCTUnwrap(liveOnly["opportunities"] as? [[String: Any]])
        var targetItem = try XCTUnwrap(bundledItems.first { $0["id"] as? String == target.id })
        targetItem["translations"] = [:]
        liveOnly["opportunities"] = [targetItem]
        liveOnly["count"] = 1
        var sourceHealth = try XCTUnwrap(liveOnly["sourceHealth"] as? [String: Any])
        var libraryHealth = try XCTUnwrap(sourceHealth["library"] as? [String: Any])
        libraryHealth["acceptedListings"] = 1
        libraryHealth["minimumAcceptedListings"] = 1
        sourceHealth["library"] = libraryHealth
        liveOnly["sourceHealth"] = sourceHealth
        var contentRights = try XCTUnwrap(liveOnly["contentRights"] as? [String: Any])
        let rightsSources = try XCTUnwrap(contentRights["sources"] as? [[String: Any]])
        var targetRights = try XCTUnwrap(
            rightsSources.first { $0["organization"] as? String == target.organization }
        )
        targetRights["records"] = 1
        contentRights["sources"] = [targetRights]
        liveOnly["contentRights"] = contentRights
        let liveOnlyData = try JSONSerialization.data(withJSONObject: liveOnly, options: [.sortedKeys])

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: liveOnlyData
        )

        let response = try await client.opportunities(query: target.title, mode: .all, filters: OpportunityFilters())

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, target.id)
        XCTAssertEqual(response.data.first?.localizedDescription(language: .fr), expectedDescription)
    }

    func testLocalOpportunitySnapshotFiltersByLanguage() throws {
        var filters = OpportunityFilters()
        filters.language = "en"

        let fullFeed = try LocalOpportunitySnapshot.loadFull()
        let response = LocalOpportunitySnapshot.filter(fullFeed.data, query: "", mode: .all, filters: filters, now: try bundledSnapshotTestNow())

        XCTAssertFalse(response.isEmpty)
        XCTAssertTrue(response.allSatisfy { $0.language.contains("en") })
    }

    func testBundledSnapshotCarriesReleaseReadyContentRightsManifest() throws {
        let response = try LocalOpportunitySnapshot.loadFull()
        let feedDate = try XCTUnwrap(FeedFreshness.date(from: response.meta?.lastUpdated))
        let restrictedIDs = try XCTUnwrap(response.contentRights?.restrictedOpportunityIDs)

        XCTAssertTrue(
            response.hasReleaseReadyContentRights(now: feedDate.addingTimeInterval(3_600)),
            "The exact bundled feed must decode with a complete, internally consistent content-rights manifest."
        )
        XCTAssertTrue(Set(restrictedIDs).isDisjoint(with: Set(response.data.map(\.id))))
    }

    func testContentRightsRejectsSelfDeclaredProviderAndUnreviewedDigest() throws {
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let rights = try legacyRights(for: bundled)
        let source = try XCTUnwrap(rights.sources.first)
        let feedDate = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated))

        func response(with changedSource: OpportunityListResponse.ContentRights.Source) -> OpportunityListResponse {
            OpportunityListResponse(
                data: bundled.data,
                meta: bundled.meta,
                sourceHealth: bundled.sourceHealth,
                contentRights: OpportunityListResponse.ContentRights(
                    termsVerifiedAt: rights.termsVerifiedAt,
                    sources: [changedSource] + Array(rights.sources.dropFirst()),
                    restrictedOpportunityIDs: rights.restrictedOpportunityIDs
                )
            )
        }

        XCTAssertTrue(response(with: source).hasReleaseReadyContentRights(now: feedDate.addingTimeInterval(3_600)))
        let unapprovedProvider = OpportunityListResponse.ContentRights.Source(
            organization: "Unapproved Library",
            sourceHost: source.sourceHost,
            records: source.records,
            status: source.status,
            basisUrl: source.basisUrl,
            conditions: source.conditions,
            termsVerifiedAt: source.termsVerifiedAt,
            termsVersion: source.termsVersion,
            termsDigestVersion: source.termsDigestVersion,
            termsSectionDigest: source.termsSectionDigest
        )
        let unreviewedDigest = OpportunityListResponse.ContentRights.Source(
            organization: source.organization,
            sourceHost: source.sourceHost,
            records: source.records,
            status: source.status,
            basisUrl: source.basisUrl,
            conditions: source.conditions,
            termsVerifiedAt: source.termsVerifiedAt,
            termsVersion: source.termsVersion,
            termsDigestVersion: source.termsDigestVersion,
            termsSectionDigest: "sha256:" + String(repeating: "0", count: 64)
        )

        // App-authored preview/support links do not authorize provider excerpts
        // hosted or self-declared on a first-party site.
        let firstPartyHostClaim = OpportunityListResponse.ContentRights.Source(
            organization: source.organization,
            sourceHost: "gta-free-stem.pages.dev",
            records: source.records,
            status: source.status,
            basisUrl: source.basisUrl,
            conditions: source.conditions,
            termsVerifiedAt: source.termsVerifiedAt,
            termsVersion: source.termsVersion,
            termsDigestVersion: source.termsDigestVersion,
            termsSectionDigest: source.termsSectionDigest
        )
        XCTAssertFalse(
            response(with: firstPartyHostClaim)
                .hasReleaseReadyContentRights(now: feedDate.addingTimeInterval(3_600))
        )

        XCTAssertFalse(
            response(with: unapprovedProvider)
                .hasReleaseReadyContentRights(now: feedDate.addingTimeInterval(3_600))
        )
        XCTAssertFalse(
            response(with: unreviewedDigest)
                .hasReleaseReadyContentRights(now: feedDate.addingTimeInterval(3_600))
        )
    }

    func testLocalOpportunitySnapshotMatchesLocaleAwareLanguageFilters() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "enca", title: "Metro STEM Day", language: ["en-CA"]),
                opportunity(id: "es", title: "Día de STEM", language: ["es"])
            ],
            query: "",
            mode: .all,
            filters: { var filters = OpportunityFilters(); filters.language = "en"; return filters }()
        )

        XCTAssertEqual(results.map(\.id), ["enca"])
    }

    func testAdultAgeFilterExcludesYouthOnlyProgramsCappedAtEighteen() {
        var filters = OpportunityFilters()
        filters.age = "18+"

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "teen-only", title: "Teen Lab", ageMin: 14, ageMax: 18),
                opportunity(id: "adult-range", title: "Young Adult Lab", ageMin: 18, ageMax: 25),
                opportunity(id: "open-adult", title: "Adult Makerspace", ageMin: 21, ageMax: nil),
                opportunity(id: "mixed-six-plus", title: "All-Audience 3D Printing", ageMin: 6, ageMax: nil),
                opportunity(id: "mixed-thirteen-plus", title: "Teen and Adult Tinkercad", ageMin: 13, ageMax: nil)
            ],
            query: "",
            mode: .all,
            filters: filters
        )

        XCTAssertEqual(
            Set(results.map(\.id)),
            Set(["adult-range", "open-adult", "mixed-six-plus", "mixed-thirteen-plus"])
        )
    }

    func testSearchMatchesMultipleTermsAcrossFields() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "match", title: "Robotics Lab", organization: "Library", city: "Toronto", tags: ["makerspace"]),
                opportunity(id: "miss", title: "Robotics Lab", organization: "Library", city: "Markham", region: "York", tags: ["makerspace"])
            ],
            query: "robotics toronto",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["match"])
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let results = LocalOpportunitySnapshot.filter(
            [opportunity(id: "accented", title: "Cafe Coding Club", organization: "STEM Cafe", description: "Robotics and AI")],
            query: "café ROBOTICS",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["accented"])
    }

    func testSearchMatchesTranslatedFieldsAndEnglishFallback() {
        let translated = opportunity(
            id: "spanish",
            title: "Library Lab",
            description: "Build machines.",
            category: "Makerspace & Fabrication",
            tags: ["makerspace"],
            translations: [
                "es": OpportunityTranslation(
                    title: "Club de robótica",
                    summary: "Aprende programación con robots.",
                    tags: ["robótica", "programación"]
                )
            ]
        )
        let englishFallback = opportunity(id: "english", title: "Robotics Workshop", tags: ["robotics"])

        let spanishResults = LocalOpportunitySnapshot.filter(
            [translated, englishFallback],
            query: "robótica",
            mode: .all,
            filters: OpportunityFilters(),
            displayLanguage: .es
        )
        let englishResults = LocalOpportunitySnapshot.filter(
            [translated, englishFallback],
            query: "robotics",
            mode: .all,
            filters: OpportunityFilters(),
            displayLanguage: .es
        )

        XCTAssertEqual(spanishResults.map(\.id), ["spanish"])
        XCTAssertEqual(englishResults.map(\.id), ["english"])
    }

    func testSearchFiltersModesAndNewFinds() {
        var filters = OpportunityFilters()
        filters.includeNewFinds = false

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "volunteer", title: "Teen Lab", volunteerHoursEligible: true, tags: ["teen"]),
                opportunity(id: "coop", title: "Co-op Lab", coopEligible: true, tags: ["shsm"]),
                opportunity(id: "review", title: "Needs Review Lab", status: "needs_review", tags: ["teen"], isNewFind: true)
            ],
            query: "lab",
            mode: .highSchool,
            filters: filters
        )

        XCTAssertEqual(Set(results.map { $0.id }), Set(["volunteer", "coop"]))
    }

    func testSearchNeverSurfacesNeedsReviewRecordsWhenNewFindsAreEnabled() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "active-new", title: "Verified New Lab", isNewFind: true),
                opportunity(id: "review", title: "Needs Review Lab", status: "needs_review", isNewFind: true)
            ],
            query: "lab",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["active-new"])
    }

    func testSearchFiltersModesAndHighSchoolTagsWithSynonyms() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "co-op", title: "Co-op Program", tags: ["co-op"]),
                opportunity(id: "high-school", title: "High-school Mentorship Lab", tags: ["high-school"]),
                opportunity(id: "other", title: "Community Lab")
            ],
            query: "",
            mode: .highSchool,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(Set(results.map { $0.id }), Set(["co-op", "high-school"]))
    }

    func testHighSchoolNavigationPreservesEachHomePathwayMode() {
        for pathwayMode in [SearchMode.volunteer, .coop, .mentorship] {
            XCTAssertEqual(
                AppNavigationModePolicy.mode(for: .highSchool, currentMode: pathwayMode),
                pathwayMode
            )
        }

        XCTAssertEqual(
            AppNavigationModePolicy.mode(for: .highSchool, currentMode: .all),
            .highSchool
        )
        XCTAssertEqual(
            AppNavigationModePolicy.mode(for: .opportunities, currentMode: .volunteer),
            .all
        )
    }

    func testSearchFiltersPathwayTogglesAndScholarships() {
        let opportunities = [
            opportunity(id: "volunteer", title: "Volunteer Lab", category: "Volunteer Hours", volunteerHoursEligible: true),
            opportunity(id: "coop", title: "Co-op Lab", category: "Co-op & SHSM", coopEligible: true),
            opportunity(id: "mentor", title: "Mentor Lab", category: "Career & Mentorship", tags: ["mentor"]),
            opportunity(id: "scholarship", title: "Scholarship Award", category: "Scholarships"),
            opportunity(id: "other", title: "General Lab")
        ]

        var filters = OpportunityFilters()
        filters.volunteerHours = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["volunteer"])

        filters = OpportunityFilters()
        filters.coop = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["coop"])

        filters = OpportunityFilters()
        filters.mentorship = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["mentor"])

        filters = OpportunityFilters()
        filters.scholarships = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["scholarship"])

        let highSchoolResults = LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .highSchool, filters: OpportunityFilters())
        XCTAssertEqual(Set(highSchoolResults.map(\.id)), Set(["volunteer", "coop", "mentor", "scholarship"]))
    }

    func testHighSchoolPathwayEligibilityExcludesAdultOnlyMentorAndHonorsBoundaries() throws {
        // Eligibility boundaries are stable synthetic facts, independent of
        // whether an old August event remains in the current published feed.
        let adultOnlyMentorID = "synthetic-adult-only-arts-mentor"
        let adultOnlyMentor = opportunity(
            id: adultOnlyMentorID,
            title: "Adult Arts Mentor Program",
            description: "An adults-only arts mentoring program.",
            startDate: "2026-08-20T10:00:00Z",
            endDate: "2026-08-21T18:00:00Z",
            ageMin: 18,
            ageMax: nil,
            tags: ["mentor"]
        )
        let beforeItsArchiveBoundary = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-20T12:00:00Z")
        )

        XCTAssertEqual(adultOnlyMentor.ageMin, 18)
        XCTAssertNil(adultOnlyMentor.ageMax)
        XCTAssertTrue(
            LocalOpportunitySnapshot.filter(
                [adultOnlyMentor],
                query: "",
                mode: .all,
                filters: OpportunityFilters(),
                now: beforeItsArchiveBoundary
            ).contains { $0.id == adultOnlyMentorID },
            "The general Browse directory must retain a current adult-only listing."
        )
        var adultAgeFilter = OpportunityFilters()
        adultAgeFilter.age = "18+"
        XCTAssertEqual(
            LocalOpportunitySnapshot.filter(
                [adultOnlyMentor],
                query: "",
                mode: .all,
                filters: adultAgeFilter,
                now: beforeItsArchiveBoundary
            ).map(\.id),
            [adultOnlyMentorID],
            "The pathway gate must not alter explicit adult searches in the general directory."
        )
        XCTAssertTrue(
            LocalOpportunitySnapshot.filter(
                [adultOnlyMentor],
                query: "",
                mode: .mentorship,
                filters: OpportunityFilters(),
                now: beforeItsArchiveBoundary
            ).isEmpty,
            "An adult-only arts mentor listing must not advertise a high-school mentorship pathway."
        )

        let boundaryRecords = [
            opportunity(id: "open-at-seventeen", title: "Mentor Program", ageMin: 17, ageMax: nil, tags: ["mentor"]),
            opportunity(id: "ends-at-fourteen", title: "Mentor Program", ageMin: 10, ageMax: 14, tags: ["mentor"]),
            opportunity(id: "starts-at-eighteen", title: "Mentor Program", ageMin: 18, ageMax: nil, tags: ["mentor"]),
            opportunity(id: "ends-at-thirteen", title: "Mentor Program", ageMin: 10, ageMax: 13, tags: ["mentor"])
        ]
        let pathwayResults = LocalOpportunitySnapshot.filter(
            boundaryRecords,
            query: "",
            mode: .mentorship,
            filters: OpportunityFilters(),
            now: beforeItsArchiveBoundary
        )

        XCTAssertEqual(Set(pathwayResults.map(\.id)), Set(["open-at-seventeen", "ends-at-fourteen"]))
        XCTAssertTrue(LocalOpportunitySnapshot.isHighSchoolPathwayEligible(boundaryRecords[0]))
        XCTAssertTrue(LocalOpportunitySnapshot.isHighSchoolPathwayEligible(boundaryRecords[1]))
        XCTAssertFalse(LocalOpportunitySnapshot.isHighSchoolPathwayEligible(boundaryRecords[2]))
        XCTAssertFalse(LocalOpportunitySnapshot.isHighSchoolPathwayEligible(boundaryRecords[3]))
    }

    func testExactBundledFeedPromotesOnlySourceBackedCurrentPathwayInventory() throws {
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let currentFeedMoment = try bundledSnapshotTestNow()

        XCTAssertEqual(bundled.data.count, 1882)
        XCTAssertEqual(
            HomePathwayInventory.availableModes(in: bundled.data, now: currentFeedMoment),
            [.volunteer]
        )
        let volunteerRows = LocalOpportunitySnapshot.filter(
            bundled.data, query: "", mode: .volunteer, filters: OpportunityFilters(), now: currentFeedMoment
        )
        XCTAssertEqual(volunteerRows.map(\.id), ["tpl-rss-6ac92852295b3b0033cb1160"])
        XCTAssertTrue(volunteerRows.allSatisfy { $0.description.contains("volunteer hours") })
        XCTAssertTrue(volunteerRows.allSatisfy(LocalOpportunitySnapshot.isHighSchoolPathwayEligible))
    }

    func testMapPinsAreSubsetOfFilteredListResults() {
        let opportunities = [
            opportunity(id: "mapped", title: "Mapped Lab", city: "Toronto", latitude: 43.654, longitude: -79.384, startDate: "2026-07-01T04:00:00.000Z"),
            opportunity(id: "list-only", title: "List Lab", city: "Toronto", startDate: "2026-07-02T04:00:00.000Z"),
            opportunity(id: "filtered-out", title: "Map Lab", city: "Markham", latitude: 43.856, longitude: -79.337, startDate: "2026-07-03T04:00:00.000Z")
        ]
        var filters = OpportunityFilters()
        filters.city = "Toronto"

        let filteredListResults = LocalOpportunitySnapshot.filter(
            opportunities,
            query: "lab",
            mode: .all,
            filters: filters,
            now: FeedFreshness.date(from: "2026-06-01T12:00:00Z")!
        )
        let mapPins = OpportunityMapProjection.pins(from: filteredListResults)

        XCTAssertEqual(filteredListResults.map(\.id), ["mapped", "list-only"])
        XCTAssertEqual(mapPins.map(\.id), ["mapped"])
        XCTAssertTrue(Set(mapPins.map(\.id)).isSubset(of: Set(filteredListResults.map(\.id))))
    }

    func testMapProjectionRejectsInvalidAndIncompleteCoordinatePairs() {
        let opportunities = [
            opportunity(id: "valid", title: "Valid Map Lab", latitude: 43.654, longitude: -79.384),
            opportunity(id: "latitude-out-of-range", title: "Bad Latitude", latitude: 91, longitude: -79.384),
            opportunity(id: "longitude-out-of-range", title: "Bad Longitude", latitude: 43.654, longitude: -181),
            opportunity(id: "non-finite", title: "Infinite Coordinate", latitude: .infinity, longitude: -79.384),
            opportunity(id: "latitude-only", title: "Half Coordinate", latitude: 43.654, longitude: nil)
        ]

        XCTAssertEqual(OpportunityMapProjection.pins(from: opportunities).map(\.id), ["valid"])
        XCTAssertTrue(OpportunityCoordinate.isValid(latitude: 43.654, longitude: -79.384))
        XCTAssertFalse(OpportunityCoordinate.isValid(latitude: 91, longitude: -79.384))
        XCTAssertFalse(OpportunityCoordinate.isValid(latitude: 43.654, longitude: -181))
        XCTAssertFalse(OpportunityCoordinate.isValid(latitude: .nan, longitude: -79.384))
        XCTAssertFalse(OpportunityCoordinate.isValid(latitude: 43.654, longitude: nil))
    }

    func testSearchSortsByRelevanceThenDate() {
        var filters = OpportunityFilters()
        filters.sort = .relevance

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "tag", title: "General Program", startDate: "2026-06-01T04:00:00.000Z", tags: ["robotics"]),
                opportunity(id: "title", title: "Robotics Program", startDate: "2026-08-01T04:00:00.000Z", tags: [])
            ],
            query: "robotics",
            mode: .all,
            filters: filters,
            now: FeedFreshness.date(from: "2026-05-01T12:00:00Z")!
        )

        XCTAssertEqual(results.map(\.id), ["title", "tag"])
    }

    func testSearchSortsByDistanceWhenLocationIsPresent() {
        var filters = OpportunityFilters()
        filters.latitude = 43.6532
        filters.longitude = -79.3832
        filters.distanceKm = 100
        filters.sort = .distance

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "far", title: "Far Lab", latitude: 43.8561, longitude: -79.3370),
                opportunity(id: "near", title: "Near Lab", latitude: 43.6540, longitude: -79.3840)
            ],
            query: "lab",
            mode: .all,
            filters: filters
        )

        XCTAssertEqual(results.map(\.id), ["near", "far"])
    }

    @MainActor
    func testSessionFormatsLocalizedDates() throws {
        let suiteName = "SessionStoreDateFormattingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let session = SessionStore(defaults: defaults, preferredLanguages: ["en-CA"])
        let formatted = session.formattedDate("2026-06-01T04:00:00.000Z")
        XCTAssertTrue(formatted.contains("6"))
        XCTAssertFalse(formatted.contains("T"))
        XCTAssertFalse(formatted.contains(".000Z"))

        let dateOnly = session.formattedDate("2026-08-06")
        XCTAssertTrue(dateOnly.contains("Aug 6"), "Date-only feed metadata must retain its declared calendar day in Toronto.")
        XCTAssertFalse(dateOnly.contains("-"))

        let offsetDateTime = session.formattedEventDateTime("2026-08-06T14:30:00-04:00")
        XCTAssertTrue(offsetDateTime.contains("2026"))
        XCTAssertTrue(offsetDateTime.contains("2:30"), offsetDateTime)

        let fractionalDateTime = session.formattedEventDateTime("2026-08-06T10:15:30.250Z")
        XCTAssertTrue(fractionalDateTime.contains("10:15"), fractionalDateTime)

        let dateOnlyEvent = session.formattedEventDateTime("2026-08-06")
        XCTAssertTrue(dateOnlyEvent.contains("2026"))
        XCTAssertFalse(dateOnlyEvent.contains(":"), dateOnlyEvent)

        let sameDaySchedule = session.formattedSchedule(
            start: "2026-08-06T14:00:00-04:00",
            end: "2026-08-06T16:00:00-04:00"
        )
        XCTAssertTrue(try XCTUnwrap(sameDaySchedule).contains("2:00"))
        XCTAssertTrue(try XCTUnwrap(sameDaySchedule).contains("4:00"))
    }

    func testAppleMapsDestinationPreservesReservedAddressCharacters() throws {
        let address = "Bayview & Eglinton, Toronto #2"
        let url = try XCTUnwrap(AppleMapsDestinationURL.make(address: address))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "maps.apple.com")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "daddr", value: address)])
        XCTAssertTrue(url.absoluteString.contains("%26"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("%23"), url.absoluteString)
    }

    func testAppleMapsDestinationPrefersCoordinatesThenUsesAReadableFallback() throws {
        let coordinateURL = try XCTUnwrap(
            AppleMapsDestinationURL.make(
                latitude: 43.6532,
                longitude: -79.3832,
                address: "Ambiguous address"
            )
        )
        let coordinateItems = try XCTUnwrap(
            URLComponents(url: coordinateURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(coordinateItems, [URLQueryItem(name: "daddr", value: "43.653200,-79.383200")])

        let fallbackURL = try XCTUnwrap(
            AppleMapsDestinationURL.make(
                address: "  ",
                fallbackComponents: ["STEM Hub", "Toronto", "Toronto"]
            )
        )
        let fallbackItems = try XCTUnwrap(
            URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(fallbackItems, [URLQueryItem(name: "daddr", value: "STEM Hub, Toronto")])
    }

    func testDateOnlyOpportunityRemainsAvailableThroughTorontoEndOfDay() throws {
        let event = Opportunity(
            id: "date-only-event",
            title: "Date-only Event",
            organization: "Community Hub",
            description: "Free event.",
            summary: nil,
            category: "Science & Engineering",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2026-08-06",
            endDate: "2026-08-06",
            deadline: nil,
            ageMin: 10,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/date-only",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )
        let duringFinalEvening = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-07T03:30:00Z"))
        let afterTorontoMidnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-07T04:01:00Z"))

        XCTAssertTrue(LocalOpportunitySnapshot.isCurrentlyAvailable(event, on: duringFinalEvening))
        XCTAssertFalse(LocalOpportunitySnapshot.isCurrentlyAvailable(event, on: afterTorontoMidnight))
    }

    func testFeedStatusShowsTheDeclaredFreshnessDateInBothiOSSurfaces() throws {
        let repoRoot = testRepositoryRoot
        let content = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))
        let browse = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift"))

        for source in [content, browse] {
            XCTAssertTrue(source.contains("store.lastUpdated"))
            XCTAssertTrue(source.contains("session.formattedDate(lastUpdated)"))
            XCTAssertTrue(source.contains("accessibilityIdentifier(\"feed-last-updated\")"))
        }
    }

    func testLayoutDirectionFollowsLanguage() {
        let rtlLanguages: [AppLanguage] = [.ar, .fa, .ur]
        for language in AppLanguage.allCases {
            let direction = language.layoutDirection
            if rtlLanguages.contains(language) {
                XCTAssertEqual(direction, .rightToLeft, "\(language.rawValue) should use RTL layout direction")
            } else {
                XCTAssertEqual(direction, .leftToRight, "\(language.rawValue) should use LTR layout direction")
            }
        }
    }

    private func makeURLSessionForStub() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let name = "GTAFreeSTEMTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testSwiftUIViewStringsUseLocalizationHelpers() throws {
        let repoRoot = testRepositoryRoot
        let sourceRoot = repoRoot.appendingPathComponent("GTAFreeSTEM")
        let swiftFiles = try FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        let literalPatterns = [
            "Text(\"",
            "Label(\"",
            "Button(\"",
            "TextField(\"",
            "SecureField(\"",
            "Toggle(\"",
            "Picker(\"",
            "NavigationLink(\"",
            "Link(\"",
            ".navigationTitle(\"",
            ".navigationBarTitle(\"",
            ".accessibilityLabel(\"",
            ".accessibilityHint(\"",
            ".accessibilityValue(\"",
            ".alert(\"",
            ".confirmationDialog(\"",
            ".placeholder(\""
        ]
        var violations = [String]()

        for file in swiftFiles {
            let contents = try String(contentsOf: file)
            for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
                for pattern in literalPatterns where line.contains(pattern) {
                    let tail = line.components(separatedBy: pattern).dropFirst().joined(separator: pattern)
                    if tail.hasPrefix("\\(") || tail.hasPrefix("\")") || line.contains(".accessibilityLabel(\"GTA FREE STEM\")") {
                        continue
                    }
                    violations.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Hardcoded visible SwiftUI strings must use session.text/AppText:\n\(violations.joined(separator: "\n"))")
    }

    func testOpportunityRowsExposeLocalizedOpenDetailsHint() throws {
        let repoRoot = testRepositoryRoot
        let browseView = repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift")
        let contents = try String(contentsOf: browseView)

        XCTAssertTrue(
            contents.contains(".accessibilityHint(session.text(\"openDetailsHint\"))"),
            "Opportunity rows should expose a localized VoiceOver hint for opening detail pages."
        )
    }

    func testEverySavedOrBrowseExtractOffersAnOriginalSourceAction() throws {
        let repoRoot = testRepositoryRoot
        let browseSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift"))
        let savedSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SavedView.swift"))
        let watchSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))

        XCTAssertTrue(browseSource.contains("ExternalOpportunityURL.make(from: opportunity.sourceUrl)"))
        XCTAssertTrue(browseSource.contains("Label(session.text(\"source\"), systemImage: \"arrow.up.right.square\")"))
        XCTAssertTrue(savedSource.contains("ExternalOpportunityURL.make(from: opportunity.sourceUrl)"))
        XCTAssertTrue(savedSource.contains("Label(session.text(\"source\"), systemImage: \"arrow.up.right.square\")"))
        XCTAssertTrue(watchSource.contains("private struct WatchOriginalSourceLink: View"))
        XCTAssertGreaterThanOrEqual(
            watchSource.components(separatedBy: "WatchOriginalSourceLink(event:").count - 1,
            3,
            "Upcoming, additional, and archived Watch extracts each need a direct original-source action."
        )
        XCTAssertTrue(watchSource.contains("Link(destination: sourceURL)"))
        XCTAssertTrue(
            browseSource.contains("\"\\(session.text(\"navOpportunities\")) · \\(session.city(for: opportunity))\"")
        )
    }

    func testMapExposesLocalizedVisibleResultCountForVoiceOver() throws {
        let repoRoot = testRepositoryRoot
        let browseView = repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift")
        let contents = try String(contentsOf: browseView)

        XCTAssertTrue(
            contents.contains(".accessibilityLabel(mapAccessibilityLabel)"),
            "The map should use a composed localized VoiceOver label instead of a generic map-only label."
        )
        XCTAssertTrue(
            contents.contains("session.text(\"map\")") &&
            contents.contains("store.opportunities.count") &&
            contents.contains("session.text(\"visible\")"),
            "The map VoiceOver label should announce localized map context and the visible result count."
        )
    }

    func testBrowseEmptyStateHasWorkingResetAndRetryActions() throws {
        let repoRoot = testRepositoryRoot
        let browseSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift"))

        XCTAssertTrue(browseSource.contains("Button(session.text(\"reset\"), action: resetEmptySearch)"))
        XCTAssertTrue(browseSource.contains("Button(session.text(\"retry\"), action: retryEmptySearch)"))
        XCTAssertTrue(browseSource.contains("store.query = \"\""))
        XCTAssertTrue(browseSource.contains("store.resetFilters()"))
        XCTAssertTrue(browseSource.contains("store.mode = surface.defaultMode"))
        XCTAssertTrue(browseSource.contains("store.refresh(cache: persistenceContext, force: true)"))
        XCTAssertTrue(browseSource.contains("if store.opportunities.isEmpty {\n            emptyOpportunityState"))
        XCTAssertTrue(browseSource.contains("isActive: isLoading && !reduceMotion"))
    }

    func testChangingOpportunityStatusUsesAnnouncementsWithoutMovingVoiceOverFocus() throws {
        let repoRoot = testRepositoryRoot
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))

        XCTAssertTrue(contentSource.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        XCTAssertTrue(contentSource.contains("AccessibilityNotification.Announcement(message).post()"))
        XCTAssertTrue(contentSource.contains("case .loading"))
        XCTAssertTrue(contentSource.contains("case let .error(message)"))
        XCTAssertTrue(contentSource.contains("case let .offline(resultCount)"))
        XCTAssertTrue(contentSource.contains("case let .results(count)"))
        XCTAssertFalse(contentSource.contains("AccessibilityNotification.LayoutChanged"))
        XCTAssertFalse(contentSource.contains("AccessibilityNotification.ScreenChanged"))
        XCTAssertFalse(contentSource.contains("accessibilityFocused"))
    }

    func testHomeAlwaysOffersBrowseAndFeedbackAndGatesPathwayPromotionsByInventory() throws {
        let repoRoot = testRepositoryRoot
        let contentSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/ContentView.swift"))
        let gridStart = try XCTUnwrap(contentSource.range(of: "private var pathwayGrid"))
        let gridEnd = try XCTUnwrap(
            contentSource.range(of: "private func pathwayRow", range: gridStart.lowerBound..<contentSource.endIndex)
        )
        let gridSource = String(contentSource[gridStart.lowerBound..<gridEnd.lowerBound])

        XCTAssertTrue(contentSource.contains("Button(action: openResults)"))
        XCTAssertTrue(gridSource.contains("pathwayRow(session.text(\"feedback\")"))
        XCTAssertTrue(gridSource.contains("if store.availableHomePathwayModes.contains(.volunteer)"))
        XCTAssertTrue(gridSource.contains("if store.availableHomePathwayModes.contains(.coop)"))
        XCTAssertTrue(gridSource.contains("if store.availableHomePathwayModes.contains(.mentorship)"))
        XCTAssertTrue(contentSource.contains("store.mode = .all"))
        XCTAssertTrue(contentSource.contains("selectedTab = .opportunities"))
        XCTAssertTrue(contentSource.contains("ForEach(Array(store.opportunities.prefix(2)))"))
        XCTAssertTrue(contentSource.contains("private var cityMenu"))
        XCTAssertTrue(contentSource.contains("private var ageMenu"))
    }

    func testBackgroundRefreshUsesCacheContextAndNewMatchNotifications() throws {
        let repoRoot = testRepositoryRoot
        let appFile = repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift")
        let appContents = String(decoding: try Data(contentsOf: appFile), as: UTF8.self)

        XCTAssertTrue(appContents.contains(".backgroundTask(.appRefresh(Self.appRefreshIdentifier))"))
        XCTAssertTrue(appContents.contains("Self.modelContainerResolution.storageAccess.allowsPersistentChanges"))
        XCTAssertTrue(appContents.contains("await opportunities.refresh(cache: context, notifyOnNewMatches: true)"))
        XCTAssertTrue(appContents.contains("Self.scheduleAppRefresh()"))

        let infoURL = repoRoot.appendingPathComponent("GTAFreeSTEM/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        )
        let identifiers = try XCTUnwrap(plist["BGTaskSchedulerPermittedIdentifiers"] as? [String])
        let backgroundModes = try XCTUnwrap(plist["UIBackgroundModes"] as? [String])

        XCTAssertTrue(identifiers.contains("com.rupayonhaldar.gtafreestem.hunt.refresh"))
        XCTAssertTrue(backgroundModes.contains("fetch"))
    }

    func testLaunchExperienceKeepsInteractiveContentOutOfHierarchyUntilFinished() throws {
        let repoRoot = testRepositoryRoot
        let appFile = repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift")
        let appContents = try String(contentsOf: appFile)

        XCTAssertNotNil(
            appContents.range(
                of: #"if isShowingLaunchExperience \{[\s\S]*?\} else \{\s*ContentView\(\)"#,
                options: .regularExpression
            ),
            "The launch experience and ContentView should be exclusive branches."
        )
        XCTAssertFalse(
            appContents.contains(".transition(.opacity)"),
            "The launch view must not cross-fade a partially loaded home screen behind it."
        )
    }

    private func opportunity(
        id: String,
        title: String,
        organization: String = "Community Library",
        description: String = "Free STEM program.",
        summary: String? = nil,
        category: String = "Coding & Robotics",
        city: String = "Toronto",
        region: String = "Toronto",
        latitude: Double? = nil,
        longitude: Double? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        deadline: String? = nil,
        ageMin: Int = 10,
        ageMax: Int? = 18,
        language: [String] = ["en"],
        status: String = "active",
        volunteerHoursEligible: Bool = false,
        coopEligible: Bool = false,
        tags: [String] = [],
        isNewFind: Bool? = nil,
        translations: [String: OpportunityTranslation] = [:],
        sourceURL: String? = nil
    ) -> Opportunity {
        let resolvedSourceURL = sourceURL ?? "https://example.com/\(id)"
        return Opportunity(
            id: id,
            title: title,
            organization: organization,
            description: description,
            summary: summary,
            category: category,
            city: city,
            region: region,
            address: nil,
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: endDate,
            deadline: deadline,
            ageMin: ageMin,
            ageMax: ageMax,
            language: language,
            cost: "Free",
            sourceUrl: resolvedSourceURL,
            registrationUrl: resolvedSourceURL,
            status: status,
            volunteerHoursEligible: volunteerHoursEligible,
            coopEligible: coopEligible,
            tags: tags,
            distanceKm: nil,
            isNewFind: isNewFind,
            sourceConfidence: nil,
            translations: translations
        )
    }

    private func approvedProviderOpportunity(
        id: String,
        title: String,
        description: String = "Free STEM program."
    ) -> Opportunity {
        opportunity(
            id: id,
            title: title,
            organization: "Markham Public Library",
            description: description,
            sourceURL: "https://markham.bibliocommons.com/events/\(id)"
        )
    }

    private func approvedProviderRightsSource(
        records: Int,
        termsVerifiedAt: String
    ) -> OpportunityListResponse.ContentRights.Source {
        .init(
            organization: "Markham Public Library",
            sourceHost: "markham.bibliocommons.com",
            records: records,
            status: "terms-permitted",
            basisUrl: "https://markham.bibliocommons.com/info/terms/",
            conditions: [
                "Automated access uses the provider's RSS/XML event feed.",
                "Every displayed extract links to its original BiblioCommons event page.",
                "GTA FREE STEM is free and does not monetize provider content."
            ],
            termsVerifiedAt: termsVerifiedAt,
            termsVersion: "2018-09-19",
            termsDigestVersion: "bibliocommons-relevant-sections-v1",
            termsSectionDigest: "sha256:451e63466c801166653f47336e236d05f9a50a3df45a917fa603e92bcd11c8a0"
        )
    }

    func testPublicationRevisionRoundTripsAndRejectsInvalidRepresentations() throws {
        let raw = try encodedFeed(id: "versioned", lastUpdated: "2026-08-20")
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        for invalid in ["", "2026-08-20", "2026-08-20T20:00:00Z", 17, true, NSNull()] as [Any] {
            var json = base
            json["publicationRevision"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(OpportunityListResponse.self, from: JSONSerialization.data(withJSONObject: json)))
        }
        var json = base
        json["publicationRevision"] = "2026-08-20T20:00:00.000Z"
        let decoded = try JSONDecoder().decode(OpportunityListResponse.self, from: JSONSerialization.data(withJSONObject: json))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertEqual(encoded["publicationRevision"] as? String, "2026-08-20T20:00:00.000Z")
        let clock = FeedFreshness.date(from: "2026-08-20T19:55:00Z")!
        XCTAssertTrue(decoded.hasValidPublicationRevision(now: clock))
        XCTAssertFalse(decoded.hasValidPublicationRevision(now: clock.addingTimeInterval(-0.001)))
    }

    func testRevisionMigrationKeepsImmutableTiesAndRejectsLegacyRollback() throws {
        func response(_ revision: String?) throws -> OpportunityListResponse {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedFeed(id: UUID().uuidString, lastUpdated: "2026-08-20")) as? [String: Any])
            json["publicationRevision"] = revision
            return try JSONDecoder().decode(OpportunityListResponse.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let legacy = try response(nil)
        let current = try response("2026-08-20T20:00:00.000Z")
        let conflict = try response("2026-08-20T20:00:00.000Z")
        XCTAssertTrue(OpportunityFeedSelection.isOlder(legacy, than: current))
        XCTAssertTrue(OpportunityFeedSelection.isOlder(conflict, than: current))
        XCTAssertFalse(OpportunityFeedSelection.isOlder(current, than: legacy))
        XCTAssertTrue(OpportunityFeedSelection.shouldPrefer(current, over: legacy))
        XCTAssertFalse(OpportunityFeedSelection.shouldPrefer(conflict, over: current))
        XCTAssertFalse(OpportunityFeedSelection.isOlder(legacy, than: try response(nil)))
    }

    func testOwnerPermissionPinsConfirmationAndScope() throws {
        let bundleURL = try XCTUnwrap(AppResources.url(forResource: "opportunities", withExtension: "json"))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundleURL)) as? [String: Any])
        let clock = try bundledSnapshotTestNow()
        for (key, value) in [("confirmationID", "invented" as Any), ("confirmedAt", "2026-10-26" as Any), ("scope", ["display-event-listings"] as Any)] {
            var json = base
            var rights = try XCTUnwrap(json["contentRights"] as? [String: Any])
            var sources = try XCTUnwrap(rights["sources"] as? [[String: Any]])
            var permission = try XCTUnwrap(sources[0]["ownerPermission"] as? [String: Any])
            permission[key] = value
            sources[0]["ownerPermission"] = permission
            rights["sources"] = sources
            json["contentRights"] = rights
            let response = try JSONDecoder().decode(OpportunityListResponse.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertFalse(response.hasReleaseReadyContentRights(now: clock))
        }
    }

    func testActualFullDescriptionTranslationSurvivesFeedSearchAndProjection() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let url = URL(string: "https://primary.example/full-translation.json")!
        let english = "Build a robot, program its motors, and test it on a maze."
        let french = "Construisez un robot, programmez ses moteurs et testez-le dans un labyrinthe."
        let complete = OpportunityTranslation(title: "Atelier de robotique", description: french)
        let merged = OpportunityTranslation(summary: "Programmez un robot.").merged(with: complete)
        XCTAssertEqual(merged.description, french)
        XCTAssertEqual(merged.title, "Atelier de robotique")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedFeed(id: "actual-full-translation", lastUpdated: "2026-08-20")) as? [String: Any])
        var rows = try XCTUnwrap(json["data"] as? [[String: Any]])
        rows[0]["description"] = english
        rows[0]["translations"] = ["fr": ["title": "Atelier de robotique", "summary": "Programmez un robot.", "description": french]]
        json["data"] = rows
        URLProtocolStub.register(responseFor: url, statusCode: 200, body: try JSONSerialization.data(withJSONObject: json))
        let client = APIClient(feedURL: url, session: makeURLSessionForStub(), now: { FeedFreshness.date(from: "2026-08-20T12:00:00Z")! })
        let response = try await client.opportunityFeed()
        let filtered = LocalOpportunitySnapshot.filter(response.data, query: "labyrinthe", mode: .all, filters: OpportunityFilters(), displayLanguage: .fr, now: FeedFreshness.date(from: "2026-08-20T12:00:00Z")!)
        XCTAssertEqual(filtered.map(\.id), ["actual-full-translation"])
        XCTAssertEqual(filtered.first?.localizedDescription(language: .fr), french)
        XCTAssertEqual(filtered.first?.description, english)
    }

    func testFuturePublicationRevisionUsesValidFallback() async throws {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        let primary = URL(string: "https://primary.example/future-revision.json")!
        let mirror = URL(string: "https://mirror.example/future-revision.json")!
        let clock = FeedFreshness.date(from: "2026-08-20T12:00:00Z")!
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedFeed(id: "future", lastUpdated: "2026-08-20")) as? [String: Any])
        json["publicationRevision"] = "2026-08-20T12:05:00.001Z"
        URLProtocolStub.register(responseFor: primary, statusCode: 200, body: try JSONSerialization.data(withJSONObject: json))
        URLProtocolStub.register(responseFor: mirror, statusCode: 200, body: try encodedFeed(id: "safe-fallback", lastUpdated: "2026-08-20"))
        let response = try await APIClient(feedURL: primary, fallbackFeedURLs: [mirror], session: makeURLSessionForStub(), now: { clock }).opportunityFeed()
        XCTAssertEqual(response.data.map(\.id), ["safe-fallback"])
    }

    private func legacyRights(for response: OpportunityListResponse) throws -> OpportunityListResponse.ContentRights {
        let rights = try XCTUnwrap(response.contentRights)
        let conditions = ["Automated access uses the provider's RSS/XML event feed.", "Every displayed extract links to its original BiblioCommons event page.", "GTA FREE STEM is free and does not monetize provider content."]
        let sources = rights.sources.map { source in
            OpportunityListResponse.ContentRights.Source(
                organization: source.organization, sourceHost: source.sourceHost, records: source.records,
                status: "terms-permitted", basisUrl: "https://\(source.sourceHost)/info/terms/", conditions: conditions,
                termsVerifiedAt: rights.termsVerifiedAt, termsVersion: "2018-09-19", termsDigestVersion: "bibliocommons-relevant-sections-v1",
                termsSectionDigest: source.sourceHost == "tpl.bibliocommons.com"
                    ? "sha256:c9b14cbd531afa09533e844274bb9f07f8042883e12b5a3990be3100ca5d4b43"
                    : "sha256:451e63466c801166653f47336e236d05f9a50a3df45a917fa603e92bcd11c8a0"
            )
        }
        return OpportunityListResponse.ContentRights(termsVerifiedAt: rights.termsVerifiedAt, sources: sources, restrictedOpportunityIDs: rights.restrictedOpportunityIDs)
    }

    private func encodedFeed(id: String, lastUpdated: String?) throws -> Data {
        try encodedFeed(ids: [id], lastUpdated: lastUpdated)
    }

    private func encodedFeed(
        ids: [String],
        lastUpdated: String?,
        sourceHealthStatus: String = "healthy",
        minimumAcceptedListings: Int = 1
    ) throws -> Data {
        let rightsTimestamp = lastUpdated ?? currentFeedTimestamp()
        return try JSONEncoder().encode(
            OpportunityListResponse(
                data: ids.map { approvedProviderOpportunity(id: $0, title: $0) },
                meta: OpportunityListResponse.Metadata(activeCount: ids.count, lastUpdated: lastUpdated),
                sourceHealth: sourceHealth(
                    publishedCount: ids.count,
                    status: sourceHealthStatus,
                    minimumAcceptedListings: minimumAcceptedListings
                ),
                contentRights: OpportunityListResponse.ContentRights(
                    termsVerifiedAt: rightsTimestamp,
                    sources: [
                        approvedProviderRightsSource(
                            records: ids.count,
                            termsVerifiedAt: rightsTimestamp
                        )
                    ],
                    restrictedOpportunityIDs: []
                )
            )
        )
    }

    private func sourceHealth(
        publishedCount: Int,
        status: String = "healthy",
        minimumAcceptedListings: Int = 1
    ) -> OpportunityListResponse.SourceHealth {
        OpportunityListResponse.SourceHealth(
            library: .init(
                status: status,
                attemptedPages: 10,
                successfulPages: 10,
                pageSuccessRatio: 1,
                minimumPageSuccessRatio: 0.75,
                acceptedListings: publishedCount,
                minimumAcceptedListings: minimumAcceptedListings
            ),
            discovery: .init(
                status: status,
                sourcesChecked: 10,
                successfulSources: 10,
                sourceSuccessRatio: 1,
                minimumSourceSuccessRatio: 0.75
            )
        )
    }

    private func currentFeedTimestamp() -> String {
        ISO8601DateFormatter().string(from: .now)
    }
}

final class OpportunityStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    @MainActor
    func testRefreshDeduplicatesConcurrentCalls() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(
                    id: "one",
                    title: "Alpha",
                    organization: "STEM Club",
                    summary: "A local science event.",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ]).data(using: .utf8)!,
            delaySeconds: 0.30
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await store.refresh(cache: nil) }
            group.addTask { await store.refresh(cache: nil) }
        }

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(store.opportunities.count, 1)
    }

    @MainActor
    func testForcedConcurrentRefreshFailurePreservesResultsAndAllowsRetry() async throws {
        let suiteName = "GTAFreeSTEMTests.ForcedFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://example.com/forced-refresh.json")!
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: makeURLSessionForStub(), now: { now }),
            defaults: defaults,
            now: { now }
        )
        _ = await store.prepareInitialSnapshot(cache: nil)
        let retainedIDs = store.opportunities.map(\.id)
        XCTAssertFalse(retainedIDs.isEmpty)
        URLProtocolStub.register(responseFor: feedURL, errorCode: .notConnectedToInternet, holdResponse: true)

        let first = Task { @MainActor in await store.refresh(cache: nil, force: true) }
        for _ in 0..<100 where URLProtocolStub.requestCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        let overlapFinished = expectation(description: "An overlapping forced refresh returns without a second request")
        let overlap = Task { @MainActor in
            await store.refresh(cache: nil, force: true)
            overlapFinished.fulfill()
        }
        let overlapWait = await XCTWaiter.fulfillment(of: [overlapFinished], timeout: 2)
        // Always release: a broken overlap gate must fail, rather than deadlock the test.
        URLProtocolStub.releaseResponse(for: feedURL)
        await first.value
        await overlap.value

        XCTAssertEqual(overlapWait, .completed)
        XCTAssertEqual(URLProtocolStub.requestCount, 1, "Forced calls must exercise the overlap guard, not the time throttle.")
        XCTAssertEqual(store.opportunities.map(\.id), retainedIDs)
        XCTAssertEqual(store.huntPhase, .offline)
        XCTAssertFalse(store.isLoading)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([
                opportunity(id: "recovered", title: "Recovered", organization: "Library", category: "STEM", city: "Toronto")
            ], lastUpdated: now).utf8)
        )
        await store.refresh(cache: nil, force: true)

        XCTAssertEqual(URLProtocolStub.requestCount, 2)
        XCTAssertEqual(store.opportunities.map(\.id), ["recovered"])
        XCTAssertEqual(store.huntPhase, .fresh)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testFailedRefreshCannotReplaceNewerMemoryWithOlderDiskCache() async throws {
        let suiteName = "GTAFreeSTEMTests.CacheRollback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let bundleDate = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated))
        let now = bundleDate.addingTimeInterval(2 * 86_400)
        let feedURL = URL(string: "https://example.com/cache-rollback.json")!
        let context = try makeInMemoryContext()
        let older = opportunity(id: "older-disk", title: "Older Disk", organization: "Library", category: "STEM", city: "Toronto")
        let retained = opportunity(id: "newer-memory", title: "Newer Memory", organization: "Library", category: "STEM", city: "Toronto")
        context.insert(OpportunityCacheRecord(
            cacheKey: "latest-opportunities",
            payload: Data(makeOpportunitiesJSON([older], lastUpdated: bundleDate.addingTimeInterval(86_400)).utf8)
        ))
        context.insert(try SavedOpportunityRecord(opportunity: retained))
        try context.save()
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: makeURLSessionForStub(), now: { now }),
            defaults: defaults,
            now: { now }
        )
        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: Data(makeOpportunitiesJSON([retained], lastUpdated: now).utf8))
        // A successful refresh without persistence leaves the disk snapshot older.
        await store.refresh(cache: nil, force: true)
        XCTAssertEqual(store.opportunities.map(\.id), [retained.id])
        let liveTimestamp = store.lastUpdated

        URLProtocolStub.register(responseFor: feedURL, errorCode: .timedOut)
        store.query = "Newer"
        await store.refresh(cache: context, force: true)

        XCTAssertEqual(store.opportunities.map(\.id), [retained.id])
        XCTAssertEqual(store.lastUpdated, liveTimestamp)
        XCTAssertEqual(store.huntPhase, .offline)
        XCTAssertFalse(store.isLoading)
        let saved = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        XCTAssertEqual(saved.first?.opportunity?.status, "active")
    }

    @MainActor
    func testRapidSequentialRefreshReFiltersCurrentResultsWithoutASecondNetworkCall() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(id: "first", title: "First Result", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto"),
                opportunity(id: "second", title: "Second Result", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).data(using: .utf8)!
        )
        await store.refresh(cache: nil)

        store.query = "Second"
        await store.refresh(cache: nil)

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(store.opportunities.map(\.id), ["second"])
        XCTAssertEqual(store.huntPhase, .fresh)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testNewMatchesUseKnownIDsToAvoidDuplicateCountsAcrossRefreshes() async throws {
        let defaults = UserDefaults.standard
        let previousKnownIDs = defaults.stringArray(forKey: "knownOpportunityIDs")
        let previousNotification = defaults.object(forKey: "lastNewOpportunityNotificationAt")
        defaults.removeObject(forKey: "knownOpportunityIDs")
        defaults.removeObject(forKey: "lastNewOpportunityNotificationAt")
        defer {
            if let previousKnownIDs {
                defaults.set(previousKnownIDs, forKey: "knownOpportunityIDs")
            } else {
                defaults.removeObject(forKey: "knownOpportunityIDs")
            }
            if let previousNotification {
                defaults.set(previousNotification, forKey: "lastNewOpportunityNotificationAt")
            } else {
                defaults.removeObject(forKey: "lastNewOpportunityNotificationAt")
            }
        }

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let payload = makeOpportunitiesJSON([
            opportunity(id: "known-once", title: "Known Once", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
        ]).data(using: .utf8)!

        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)
        let firstStore = OpportunityStore(api: client)
        await firstStore.refresh(cache: nil)
        XCTAssertEqual(firstStore.newMatchesCount, 1)

        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)
        let secondStore = OpportunityStore(api: client)
        await secondStore.refresh(cache: nil)
        XCTAssertEqual(secondStore.newMatchesCount, 0)
    }

    @MainActor
    func testFilteredRefreshRetainsFullFeedIDsSoChangingHuntDoesNotCreateFalseNewMatches() async throws {
        let suiteName = "GTAFreeSTEMTests.FilteredKnownIDs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let payload = makeOpportunitiesJSON([
            opportunity(id: "alpha", title: "Alpha Lab", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto"),
            opportunity(id: "beta", title: "Beta Lab", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
        ]).data(using: .utf8)!
        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)

        let alphaStore = OpportunityStore(api: client, defaults: defaults)
        alphaStore.query = "Alpha"
        await alphaStore.refresh(cache: nil)

        XCTAssertEqual(alphaStore.opportunities.map(\.id), ["alpha"])
        XCTAssertEqual(alphaStore.newMatchesCount, 1)
        XCTAssertEqual(Set(defaults.stringArray(forKey: "knownOpportunityIDs") ?? []), ["alpha", "beta"])

        let betaStore = OpportunityStore(api: client, defaults: defaults)
        betaStore.query = "Beta"
        await betaStore.refresh(cache: nil)

        XCTAssertEqual(betaStore.opportunities.map(\.id), ["beta"])
        XCTAssertEqual(betaStore.newMatchesCount, 0)
    }

    @MainActor
    func testInitialSnapshotSeedsKnownIDsBeforeBackgroundRefresh() async throws {
        let now = try bundledSnapshotTestNow()
        let suiteName = "GTAFreeSTEMTests.InitialKnownIDBaseline.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundledFeed = try LocalOpportunitySnapshot.loadFull()
        let retainedOpportunity = try XCTUnwrap(bundledFeed.data.first)
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let delivery = NewMatchNotificationDeliveryStub(outcomes: [true])
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: session, now: { now }),
            defaults: defaults,
            notificationDelivery: delivery,
            now: { now }
        )
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([retainedOpportunity], lastUpdated: now).utf8)
        )

        let prepared = await store.prepareInitialSnapshot(cache: nil)

        XCTAssertTrue(prepared)
        XCTAssertTrue(defaults.stringArray(forKey: "knownOpportunityIDs")?.contains(retainedOpportunity.id) == true)

        await store.refresh(cache: nil, notifyOnNewMatches: true)

        let deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(store.newMatchesCount, 0)
        XCTAssertEqual(deliveryCount, 0)
        XCTAssertNil(defaults.object(forKey: "lastNewOpportunityNotificationAt"))
    }

    @MainActor
    func testBackgroundOnlyLaunchSeedsTrustedBaselineBeforeNotifying() async throws {
        let now = try bundledSnapshotTestNow()
        let suiteName = "GTAFreeSTEMTests.BackgroundOnlyKnownIDBaseline.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundledFeed = try LocalOpportunitySnapshot.loadFull()
        let retainedOpportunity = try XCTUnwrap(bundledFeed.data.first)
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let delivery = NewMatchNotificationDeliveryStub(outcomes: [true])
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: session, now: { now }),
            defaults: defaults,
            notificationDelivery: delivery,
            now: { now }
        )
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([retainedOpportunity], lastUpdated: now).utf8)
        )

        // Model the system launching only the BGAppRefresh task: no WindowGroup
        // task or prepareInitialSnapshot call runs before the live request.
        await store.refresh(cache: nil, notifyOnNewMatches: true)

        let deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(store.newMatchesCount, 0)
        XCTAssertEqual(deliveryCount, 0)
        XCTAssertNil(defaults.object(forKey: "lastNewOpportunityNotificationAt"))
        XCTAssertTrue(defaults.stringArray(forKey: "knownOpportunityIDs")?.contains(retainedOpportunity.id) == true)
    }

    @MainActor
    func testBackgroundOnlyLaunchStillNotifiesForItemNewerThanTrustedBaseline() async throws {
        let now = try bundledSnapshotTestNow()
        let suiteName = "GTAFreeSTEMTests.BackgroundOnlyNewMatch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundledFeed = try LocalOpportunitySnapshot.loadFull()
        let retainedOpportunity = try XCTUnwrap(bundledFeed.data.first)
        let newOpportunity = opportunity(
            id: "newer-than-bundled-baseline",
            title: "New Public Lab",
            organization: "STEM Club",
            category: "Coding & Robotics",
            city: "Toronto"
        )
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let delivery = NewMatchNotificationDeliveryStub(outcomes: [true])
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: session, now: { now }),
            defaults: defaults,
            notificationDelivery: delivery,
            now: { now }
        )
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([retainedOpportunity, newOpportunity], lastUpdated: now).utf8)
        )

        await store.refresh(cache: nil, notifyOnNewMatches: true)

        let deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(store.newMatchesCount, 1)
        XCTAssertEqual(deliveryCount, 1)
        XCTAssertNotNil(defaults.object(forKey: "lastNewOpportunityNotificationAt"))
    }

    @MainActor
    func testNotificationThrottleIsRecordedOnlyAfterSuccessfulDelivery() async throws {
        let suiteName = "GTAFreeSTEMTests.NotificationThrottle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["known-baseline"], forKey: "knownOpportunityIDs")

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let delivery = NewMatchNotificationDeliveryStub(outcomes: [false, true, true])
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: session),
            defaults: defaults,
            notificationDelivery: delivery
        )

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([
                opportunity(id: "first-new", title: "First New", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).utf8)
        )
        await store.refresh(cache: nil, notifyOnNewMatches: true)

        var deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(deliveryCount, 1)
        XCTAssertNil(defaults.object(forKey: "lastNewOpportunityNotificationAt"))

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([
                opportunity(id: "second-new", title: "Second New", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).utf8)
        )
        await store.refresh(cache: nil, notifyOnNewMatches: true, force: true)

        deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(deliveryCount, 2)
        XCTAssertNotNil(defaults.object(forKey: "lastNewOpportunityNotificationAt") as? TimeInterval)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([
                opportunity(id: "third-new", title: "Third New", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).utf8)
        )
        await store.refresh(cache: nil, notifyOnNewMatches: true, force: true)

        deliveryCount = await delivery.deliveryCount()
        XCTAssertEqual(deliveryCount, 2)
    }

    func testKnownIDRetentionKeepsCurrentFeedStableBeyondHistoryCap() {
        let historical = (0..<2_600).map { "historical-\($0)" }
        let current = ["current-a", "current-b"]

        let first = KnownOpportunityHistory.merging(
            currentIDs: current,
            previousIDs: historical + current
        )
        XCTAssertEqual(first.newCount, 0)
        XCTAssertEqual(first.retainedIDs.count, KnownOpportunityHistory.maximumCount)
        XCTAssertTrue(Set(current).isSubset(of: Set(first.retainedIDs)))

        let relaunched = KnownOpportunityHistory.merging(
            currentIDs: Array(current.reversed()),
            previousIDs: Array(first.retainedIDs.reversed())
        )
        XCTAssertEqual(relaunched.newCount, 0)
        XCTAssertTrue(Set(current).isSubset(of: Set(relaunched.retainedIDs)))
    }

    @MainActor
    func testNewerBundledFeedReplacesOlderPersistedCacheAfterAppUpdate() async throws {
        let now = try bundledSnapshotTestNow()
        let context = try makeInMemoryContext()
        let oldCache = OpportunityListResponse(
            data: [
                opportunity(
                    id: "old-cache-only",
                    title: "Old Cache",
                    organization: "Old Source",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ],
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: "2025-01-01")
        )
        context.insert(
            OpportunityCacheRecord(
                cacheKey: "latest-opportunities",
                payload: try JSONEncoder().encode(oldCache)
            )
        )
        try context.save()

        let store = OpportunityStore(api: APIClient(now: { now }), now: { now })
        let prepared = await store.prepareInitialSnapshot(cache: context)

        XCTAssertTrue(prepared)
        XCTAssertFalse(store.opportunities.isEmpty)
        XCTAssertFalse(store.opportunities.contains { $0.id == "old-cache-only" })
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
    }

    @MainActor
    func testNewerPersistedCacheRemainsPreferredToBundledFeed() async throws {
        let context = try makeInMemoryContext()
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let bundledDate = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated))
        let newerDate = ISO8601DateFormatter().string(from: bundledDate.addingTimeInterval(86_400))
        let newerCache = OpportunityListResponse(
            data: [
                opportunity(
                    id: "newer-cache",
                    title: "Newer Cache",
                    organization: "Fresh Source",
                    category: "Science & Engineering",
                    city: "Toronto"
                )
            ],
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: newerDate)
        )
        context.insert(
            OpportunityCacheRecord(
                cacheKey: "latest-opportunities",
                payload: try JSONEncoder().encode(newerCache)
            )
        )
        try context.save()

        let store = OpportunityStore(api: APIClient())
        let prepared = await store.prepareInitialSnapshot(cache: context)

        XCTAssertTrue(prepared)
        XCTAssertEqual(store.opportunities.map(\.id), ["newer-cache"])
        XCTAssertEqual(store.dataSourceLabel, .savedAppCache)
    }

    func testSameDayPublicationOrderRejectsLaggingMirrorAndAcceptsCorrection() throws {
        func revised(_ id: String, _ revision: String) throws -> OpportunityListResponse {
            let row = opportunity(id: id, title: id, organization: "Markham Public Library", category: "STEM", city: "Markham")
            let data = Data(makeOpportunitiesJSON([row], lastUpdated: FeedFreshness.date(from: "2026-08-20")!).utf8)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["publicationRevision"] = revision
            return try JSONDecoder().decode(OpportunityListResponse.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let old = try revised("old-mirror", "2026-08-20T16:26:56.721Z")
        let current = try revised("current-program", "2026-08-20T20:55:11.491Z")
        XCTAssertTrue(OpportunityFeedSelection.isOlder(old, than: current))
        XCTAssertFalse(OpportunityFeedSelection.isOlder(current, than: old))
        XCTAssertTrue(OpportunityFeedSelection.shouldPrefer(current, over: old))
        XCTAssertFalse(OpportunityFeedSelection.shouldPrefer(old, over: current))
    }

    @MainActor
    func testIdenticalPublicationRefreshRecordsOnlineSuccessWithoutRewritingFeed() async throws {
        let context = try makeInMemoryContext()
        let clock = try bundledSnapshotTestNow()
        let url = URL(string: "https://primary.example/identical.json")!
        let bundleURL = try XCTUnwrap(AppResources.url(forResource: "opportunities", withExtension: "json"))
        URLProtocolStub.register(responseFor: url, statusCode: 200, body: try Data(contentsOf: bundleURL))
        let store = OpportunityStore(api: APIClient(feedURL: url, session: makeURLSessionForStub(), now: { clock }), now: { clock })
        _ = await store.prepareInitialSnapshot(cache: context)
        let accepted = store.opportunities
        XCTAssertNil(store.lastSuccessfulHuntAt)
        await store.refresh(cache: context, force: true)
        XCTAssertEqual(store.opportunities, accepted)
        XCTAssertEqual(store.lastSuccessfulHuntAt, clock)
        XCTAssertEqual(store.dataSourceLabel, .publicLiveFeed)
        XCTAssertEqual(store.huntPhase, .fresh)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OpportunityCacheRecord>()).isEmpty)
    }

    @MainActor
    func testConflictingEqualPublicationNeverClaimsIdenticalOnlineSuccess() async throws {
        let context = try makeInMemoryContext()
        let clock = try bundledSnapshotTestNow()
        let url = URL(string: "https://primary.example/conflicting.json")!
        let bundleURL = try XCTUnwrap(AppResources.url(forResource: "opportunities", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundleURL)) as? [String: Any])
        var rows = try XCTUnwrap(json["opportunities"] as? [[String: Any]])
        rows[0]["title"] = "Conflicting equal revision body"
        json["opportunities"] = rows
        URLProtocolStub.register(responseFor: url, statusCode: 200, body: try JSONSerialization.data(withJSONObject: json))
        let store = OpportunityStore(api: APIClient(feedURL: url, session: makeURLSessionForStub(), now: { clock }), now: { clock })
        _ = await store.prepareInitialSnapshot(cache: context)
        let accepted = store.opportunities
        await store.refresh(cache: context, force: true)
        XCTAssertEqual(store.opportunities, accepted)
        XCTAssertNil(store.lastSuccessfulHuntAt)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OpportunityCacheRecord>()).isEmpty)
    }

    @MainActor
    func testFuturePublicationInPersistedCacheCannotPinTheStore() async throws {
        let context = try makeInMemoryContext()
        let clock = try bundledSnapshotTestNow()
        let row = opportunity(id: "poisoned-future", title: "Future cache", organization: "Markham Public Library", category: "STEM", city: "Markham")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(makeOpportunitiesJSON([row], lastUpdated: clock).utf8)) as? [String: Any])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        json["publicationRevision"] = formatter.string(from: clock.addingTimeInterval(86400))
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: try JSONSerialization.data(withJSONObject: json)))
        try context.save()
        let store = OpportunityStore(api: APIClient(), now: { clock })
        let prepared = await store.prepareInitialSnapshot(cache: context)
        XCTAssertTrue(prepared)
        XCTAssertFalse(store.opportunities.contains { $0.id == "poisoned-future" })
        XCTAssertFalse(store.opportunities.isEmpty)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
    }

    @MainActor
    func testOlderLiveFeedCannotReplaceNewerRetainedFeedOrRemoveSavedEvents() async throws {
        let context = try makeInMemoryContext()
        let retainedSaved = opportunity(
            id: "retained-newer-saved",
            title: "Retained Newer Saved Event",
            organization: "Current Source",
            category: "Science & Engineering",
            city: "Toronto"
        )
        context.insert(try SavedOpportunityRecord(opportunity: retainedSaved))
        try context.save()

        let bundled = try LocalOpportunitySnapshot.loadFull()
        let bundledDate = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated))
        let now = try bundledSnapshotTestNow()
        let expectedBundledID = try XCTUnwrap(bundled.data.first?.id)
        let olderLive = opportunity(
            id: "older-live-only",
            title: "Older Live Event",
            organization: "Old Source",
            category: "Coding & Robotics",
            city: "Toronto"
        )
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(
                makeOpportunitiesJSON(
                    [olderLive],
                    lastUpdated: bundledDate.addingTimeInterval(-86_400)
                ).utf8
            )
        )
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: makeURLSessionForStub(), now: { now }),
            now: { now }
        )

        let prepared = await store.prepareInitialSnapshot(cache: context)
        XCTAssertTrue(prepared)
        await store.refresh(cache: context, force: true)

        XCTAssertTrue(store.opportunities.contains { $0.id == expectedBundledID })
        XCTAssertFalse(store.opportunities.contains { $0.id == "older-live-only" })
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        let saved = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        XCTAssertEqual(saved.first { $0.opportunityID == retainedSaved.id }?.opportunity?.status, "active")
    }

    @MainActor
    func testValidatedLiveRefreshUpdatesCancelsAndArchivesSavedEvents() async throws {
        let context = try makeInMemoryContext()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let savedRecords = [
            try SavedOpportunityRecord(
                opportunity: opportunity(
                    id: "saved-updated",
                    title: "Old Title",
                    organization: "Community Hub",
                    category: "Coding & Robotics",
                    city: "Toronto"
                ),
                savedAt: savedAt
            ),
            try SavedOpportunityRecord(
                opportunity: opportunity(
                    id: "saved-cancelled",
                    title: "Soon Cancelled",
                    organization: "Community Hub",
                    category: "Science & Engineering",
                    city: "Toronto"
                ),
                savedAt: savedAt
            ),
            try SavedOpportunityRecord(
                opportunity: opportunity(
                    id: "saved-removed",
                    title: "Removed Event",
                    organization: "Community Hub",
                    category: "Science & Engineering",
                    city: "Toronto"
                ),
                savedAt: savedAt
            )
        ]
        savedRecords.forEach(context.insert)
        try context.save()

        let updated = opportunity(
            id: "saved-updated",
            title: "Updated Title",
            organization: "Community Hub",
            category: "Coding & Robotics",
            city: "Mississauga",
            address: "100 Updated Street"
        )
        let cancelled = opportunity(
            id: "saved-cancelled",
            title: "Soon Cancelled",
            organization: "Community Hub",
            category: "Science & Engineering",
            city: "Toronto",
            status: "cancelled"
        )

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([updated, cancelled]).utf8)
        )
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: makeURLSessionForStub())
        )
        await store.refresh(cache: context)

        let refreshed = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        let byID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.opportunityID, $0) })
        XCTAssertEqual(byID["saved-updated"]?.opportunity?.title, "Updated Title")
        XCTAssertEqual(byID["saved-updated"]?.opportunity?.city, "Mississauga")
        XCTAssertEqual(byID["saved-updated"]?.opportunity?.address, "100 Updated Street")
        XCTAssertEqual(byID["saved-cancelled"]?.opportunity?.status, "cancelled")
        XCTAssertTrue(LocalOpportunitySnapshot.isArchived(try XCTUnwrap(byID["saved-cancelled"]?.opportunity)))
        XCTAssertEqual(byID["saved-removed"]?.opportunity?.status, "removed")
        XCTAssertTrue(LocalOpportunitySnapshot.isArchived(try XCTUnwrap(byID["saved-removed"]?.opportunity)))
        XCTAssertEqual(byID["saved-updated"]?.savedAt, savedAt)
        XCTAssertEqual(byID["saved-cancelled"]?.savedAt, savedAt)
        XCTAssertEqual(byID["saved-removed"]?.savedAt, savedAt)
    }

    @MainActor
    func testRefreshFallsBackToCachedResponse() async throws {
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let store = OpportunityStore(api: client, now: { now })
        let context = try makeInMemoryContext()

        let cached = OpportunityListResponse(
            data: [
                opportunity(
                    id: "cached",
                    title: "Cached Event",
                    organization: "Community Hub",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ],
            meta: OpportunityListResponse.Metadata(
                activeCount: 1,
                lastUpdated: ISO8601DateFormatter().string(from: now)
            )
        )
        let payload = try JSONEncoder().encode(cached)
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: payload))
        try context.save()

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 500,
            body: "fail".data(using: .utf8)!
        )

        await store.refresh(cache: context)

        XCTAssertEqual(store.opportunities.map(\.id), ["cached"])
        XCTAssertEqual(store.dataSourceLabel, DataSource.savedAppCache)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testFreshEmptyFeedFallsBackToCachedResponse() async throws {
        let now = try bundledSnapshotTestNow().addingTimeInterval(2 * 86_400)
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let store = OpportunityStore(api: client, now: { now })
        let context = try makeInMemoryContext()
        let bundled = try LocalOpportunitySnapshot.loadFull()
        let bundledDate = try XCTUnwrap(FeedFreshness.date(from: bundled.meta?.lastUpdated))
        let newerCacheDate = ISO8601DateFormatter().string(
            from: bundledDate.addingTimeInterval(86_400)
        )

        let cached = OpportunityListResponse(
            data: [
                opportunity(
                    id: "cached-after-empty-live-response",
                    title: "Cached Event",
                    organization: "Community Hub",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ],
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: newerCacheDate)
        )
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: try JSONEncoder().encode(cached)))
        try context.save()

        let emptyPayload = """
        {"count":0,"lastDataChange":"\(ISO8601DateFormatter().string(from: now))","opportunities":[]}
        """.data(using: .utf8)!
        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: emptyPayload)

        await store.refresh(cache: context)

        XCTAssertEqual(store.opportunities.map(\.id), ["cached-after-empty-live-response"])
        XCTAssertEqual(store.dataSourceLabel, .savedAppCache)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testBootstrapRefreshesCachedFeedAtEachColdLaunch() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let context = try makeInMemoryContext()

        let cached = opportunity(
            id: "cached-launch-result",
            title: "Cached Launch Result",
            organization: "Community Hub",
            category: "Coding & Robotics",
            city: "Toronto"
        )
        context.insert(
            OpportunityCacheRecord(
                cacheKey: "latest-opportunities",
                payload: Data(makeOpportunitiesJSON([cached]).utf8)
            )
        )
        try context.save()

        let fresh = opportunity(
            id: "fresh-launch-result",
            title: "Fresh Launch Result",
            organization: "Live Source",
            category: "Science & Engineering",
            city: "Mississauga"
        )
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([fresh]).data(using: .utf8)!
        )

        await store.bootstrap(cache: context)

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(store.opportunities.map(\.id), ["fresh-launch-result"])
        XCTAssertEqual(store.dataSourceLabel, .publicLiveFeed)
        XCTAssertEqual(store.huntPhase, .fresh)
    }

    @MainActor
    func testBootstrapShowsBundledSnapshotBeforeSlowLiveRefreshCompletes() async throws {
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let store = OpportunityStore(api: client, now: { now })
        let live = opportunity(
            id: "slow-live-result",
            title: "Slow Live Result",
            organization: "Live Source",
            category: "Science & Engineering",
            city: "Mississauga"
        )

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([live], lastUpdated: now).utf8),
            // The bundle is deliberately decoded off the main actor. Give the
            // test a genuinely slow source so it validates the intended state
            // rather than racing against simulator disk and decoder speed.
            delaySeconds: 3.0
        )

        let bootstrap = Task { @MainActor in
            await store.bootstrap(cache: nil)
        }
        for _ in 0..<48 where store.opportunities.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertGreaterThan(store.opportunities.count, 0)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)

        await bootstrap.value
        XCTAssertEqual(store.opportunities.map(\.id), ["slow-live-result"])
        XCTAssertEqual(store.dataSourceLabel, .publicLiveFeed)
    }

    @MainActor
    func testPrepareInitialSnapshotMakesBundledResultsUsableWithoutNetwork() async throws {
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let store = OpportunityStore(api: APIClient(feedURL: feedURL, session: session, now: { now }), now: { now })

        let prepared = await store.prepareInitialSnapshot(cache: nil)

        XCTAssertTrue(prepared)
        XCTAssertGreaterThan(store.opportunities.count, 0)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
        XCTAssertEqual(store.availableHomePathwayModes, [.volunteer])
        let volunteerRows = LocalOpportunitySnapshot.filter(store.opportunities, query: "", mode: .volunteer, filters: OpportunityFilters(), now: now)
        XCTAssertEqual(volunteerRows.map(\.id), ["tpl-rss-6ac92852295b3b0033cb1160"])
    }

    @MainActor
    func testPublishedHomePathwayInventoryUsesRetainedFullFeed() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let store = OpportunityStore(
            api: APIClient(feedURL: feedURL, session: makeURLSessionForStub())
        )
        let feed = [
            opportunity(
                id: "volunteer-pathway",
                title: "Community Hours Lab",
                organization: "Community Hub",
                category: "Volunteer Hours",
                city: "Toronto",
                volunteerHoursEligible: true
            ),
            opportunity(
                id: "coop-pathway",
                title: "Student Placement Lab",
                organization: "Community Hub",
                category: "Co-op & SHSM",
                city: "Toronto",
                coopEligible: true
            ),
            opportunity(
                id: "mentorship-pathway",
                title: "Youth Mentor Lab",
                organization: "Community Hub",
                category: "Career & Mentorship",
                city: "Toronto",
                tags: ["mentor"]
            ),
            opportunity(
                id: "adult-mentor",
                title: "Adult Mentor Workshop",
                organization: "Community Hub",
                category: "Career & Mentorship",
                city: "Toronto",
                ageMin: 18,
                ageMax: nil,
                tags: ["mentor"]
            )
        ]
        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON(feed).utf8)
        )

        await store.refresh(cache: nil)

        XCTAssertEqual(store.availableHomePathwayModes, [.volunteer, .coop, .mentorship])

        store.query = "no retained record matches this hunt"
        await store.refresh(cache: nil)

        XCTAssertTrue(store.opportunities.isEmpty)
        XCTAssertEqual(
            store.availableHomePathwayModes,
            [.volunteer, .coop, .mentorship],
            "Home inventory must describe the retained published feed, not the current query's result subset."
        )
    }

    @MainActor
    func testSearchUsesBundledFullFeedWhileLiveRefreshIsInFlight() async throws {
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let store = OpportunityStore(api: client, now: { now })
        let bundledFeed = try LocalOpportunitySnapshot.loadFull()
        let initiallyVisible = LocalOpportunitySnapshot.filter(
            bundledFeed.data,
            query: "",
            mode: .all,
            filters: OpportunityFilters(),
            now: now
        )
        let searchableOpportunity = try XCTUnwrap(initiallyVisible.first)
        let live = opportunity(
            id: "delayed-live-result",
            title: "Delayed Live Result",
            organization: "Live Source",
            category: searchableOpportunity.category,
            city: searchableOpportunity.city
        )

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: Data(makeOpportunitiesJSON([live], lastUpdated: now).utf8),
            holdResponse: true
        )

        // This matches the real launch contract: GTAFreeSTEMApp prepares the
        // snapshot before ContentView starts its background live refresh.
        let prepared = await store.prepareInitialSnapshot(cache: nil)
        XCTAssertTrue(prepared)
        XCTAssertGreaterThan(store.opportunities.count, 0)

        let liveRefresh = Task { @MainActor in
            await store.refresh(cache: nil)
        }
        defer { URLProtocolStub.releaseResponse(for: feedURL) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.isLoading)

        store.query = searchableOpportunity.title
        let expectedIDs = LocalOpportunitySnapshot.filter(
            bundledFeed.data,
            query: store.query,
            mode: store.mode,
            filters: store.filters,
            now: now
        ).map(\.id)
        await store.refresh(cache: nil)

        XCTAssertEqual(store.opportunities.map(\.id), expectedIDs)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertTrue(store.isLoading)

        URLProtocolStub.releaseResponse(for: feedURL)
        await liveRefresh.value
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testRefreshFallsBackToBundledSnapshotWithoutCache() async throws {
        let now = try bundledSnapshotTestNow()
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session, now: { now })
        let store = OpportunityStore(api: client, now: { now })

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 500,
            body: "failed".data(using: .utf8)!
        )

        await store.refresh(cache: nil)

        XCTAssertGreaterThan(store.opportunities.count, 0)
        XCTAssertEqual(store.dataSourceLabel, DataSource.previewDatabase)
        XCTAssertEqual(store.huntPhase, .offline)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testLastHuntRestoresAllFiltersAndCachedResults() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let context = try makeInMemoryContext()

        var filters = OpportunityFilters()
        filters.region = "Toronto"
        filters.city = "Toronto"
        filters.category = "Career & Mentorship"
        filters.age = "16"
        filters.language = "es"
        filters.latitude = 43.6532
        filters.longitude = -79.3832
        filters.distanceKm = 50
        filters.sort = .distance
        filters.includeNewFinds = false
        filters.volunteerHours = true
        filters.coop = true
        filters.mentorship = true
        filters.scholarships = true
        filters.blackFocused = true
        filters.girlsFocused = true
        filters.indigenousFocused = true
        filters.leadership = true

        store.query = "leadership"
        store.mode = .mentorship
        store.filters = filters

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                Opportunity(
                    id: "restored",
                    title: "Leadership Mentorship Lab",
                    organization: "Community Hub",
                    description: "Black girls Indigenous leadership mentorship.",
                    summary: "Black girls Indigenous leadership mentorship.",
                    category: "Career & Mentorship",
                    city: "Toronto",
                    region: "Toronto",
                    address: nil,
                    latitude: 43.6540,
                    longitude: -79.3840,
                    startDate: nil,
                    endDate: nil,
                    deadline: nil,
                    ageMin: 14,
                    ageMax: 18,
                    language: ["es"],
                    cost: "Free",
                    sourceUrl: "https://example.com/restored",
                    registrationUrl: "https://example.com/restored",
                    status: "active",
                    volunteerHoursEligible: true,
                    coopEligible: true,
                    tags: ["black", "girls", "indigenous", "leadership", "mentor", "scholarship"],
                    distanceKm: nil,
                    isNewFind: nil,
                    sourceConfidence: nil
                )
            ]).data(using: .utf8)!
        )

        await store.refresh(cache: context)

        let restoredStore = OpportunityStore(api: client)
        await restoredStore.restoreLastHuntIfNeeded(in: context)

        XCTAssertEqual(restoredStore.query, "leadership")
        XCTAssertEqual(restoredStore.mode, .mentorship)
        XCTAssertEqual(restoredStore.filters, filters)
        XCTAssertEqual(restoredStore.opportunities.map(\.id), ["restored"])
        XCTAssertEqual(restoredStore.dataSourceLabel, DataSource.savedAppCache)
    }

    @MainActor
    func testLegacyEighteenPlusSavedHuntMigratesToAdultBucket() async throws {
        let context = try makeInMemoryContext()
        var legacyFilters = OpportunityFilters()
        legacyFilters.age = "18"
        context.insert(
            SavedHuntRecord(
                cacheKey: "last-hunt",
                query: "",
                mode: .all,
                filters: legacyFilters
            )
        )
        try context.save()

        let restoredStore = OpportunityStore(api: APIClient())
        await restoredStore.restoreLastHuntIfNeeded(in: context)

        XCTAssertEqual(restoredStore.filters.age, "18+")
    }

    @MainActor
    func testLocalSavedOpportunityCanBeToggledWithoutNetwork() throws {
        let context = try makeInMemoryContext()
        let opportunity = opportunity(
            id: "saved-on-device",
            title: "Local Save",
            organization: "Community Lab",
            category: "Coding & Robotics",
            city: "Toronto"
        )

        XCTAssertTrue(try SavedOpportunityLibrary.toggle(opportunity, in: context))
        let records = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.opportunity?.id, opportunity.id)
        XCTAssertTrue(SavedOpportunityLibrary.isSaved(opportunity, in: records))

        XCTAssertFalse(try SavedOpportunityLibrary.toggle(opportunity, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedOpportunityRecord>()).isEmpty)
    }

    @MainActor
    func testRightsRestrictedSavedPayloadIsDeletedWhileOrdinaryArchiveIsPreserved() throws {
        let context = try makeInMemoryContext()
        let restricted = opportunity(
            id: "rights-restricted",
            title: "Restricted Provider Copy",
            organization: "Restricted Provider",
            category: "Science & Engineering",
            city: "Toronto"
        )
        let ordinaryArchive = opportunity(
            id: "ordinary-archive",
            title: "Past Saved Event",
            organization: "Permitted Provider",
            category: "Coding & Robotics",
            city: "Toronto",
            status: "removed"
        )
        context.insert(try SavedOpportunityRecord(opportunity: restricted))
        context.insert(try SavedOpportunityRecord(opportunity: ordinaryArchive))
        try context.save()

        let mutations = try SavedOpportunityLibrary.reconcile(
            with: [],
            in: context,
            markMissingAsUnavailable: false,
            restrictedOpportunityIDs: [restricted.id]
        )

        let retained = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        XCTAssertEqual(mutations, 1)
        XCTAssertEqual(retained.map(\.opportunityID), [ordinaryArchive.id])
        XCTAssertEqual(retained.first?.opportunity?.title, ordinaryArchive.title)
    }

    @MainActor
    func testClearingPersonalHistoryKeepsPublicCacheButRemovesHuntAndSeenRecords() async throws {
        let context = try makeInMemoryContext()
        let opportunity = opportunity(
            id: "cached-public-opportunity",
            title: "Cached Public Opportunity",
            organization: "Community Lab",
            category: "Coding & Robotics",
            city: "Toronto"
        )
        let payload = makeOpportunitiesJSON([opportunity]).data(using: .utf8)!
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: payload))
        context.insert(SavedHuntRecord(cacheKey: "last-hunt", query: "robotics", mode: .all, filters: OpportunityFilters()))
        context.insert(SeenOpportunityRecord(opportunityID: opportunity.id))
        try context.save()

        let client = APIClient(feedURL: URL(string: "https://example.com/opportunities.json")!, session: makeURLSessionForStub())
        let store = OpportunityStore(api: client)
        store.query = "robotics"
        try await store.clearPersonalHistory(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedHuntRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SeenOpportunityRecord>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OpportunityCacheRecord>()).count, 1)
        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.opportunities.map(\.id), [opportunity.id])
    }

    @MainActor
    func testCacheKeepsTheWholeFeedSoOfflineSearchesStillWork() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let context = try makeInMemoryContext()

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(id: "alpha", title: "Alpha Robotics", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto"),
                opportunity(id: "beta", title: "Beta Biology", organization: "Science Hub", category: "Science & Engineering", city: "Toronto")
            ]).data(using: .utf8)!
        )

        let firstStore = OpportunityStore(api: client)
        firstStore.query = "alpha"
        await firstStore.refresh(cache: context)
        XCTAssertEqual(firstStore.opportunities.map(\.id), ["alpha"])

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 500,
            body: Data("offline".utf8)
        )

        let offlineStore = OpportunityStore(api: client)
        offlineStore.query = "beta"
        await offlineStore.refresh(cache: context)

        XCTAssertEqual(offlineStore.opportunities.map(\.id), ["beta"])
        XCTAssertEqual(offlineStore.dataSourceLabel, .savedAppCache)
    }

    func testDefaultSearchNeverShowsAnActiveButExpiredOpportunity() {
        let expired = Opportunity(
            id: "expired-active",
            title: "Past workshop",
            organization: "Community Lab",
            description: "An old workshop.",
            summary: nil,
            category: "Science & Engineering",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2020-01-01T09:00:00Z",
            endDate: "2020-01-02T17:00:00Z",
            deadline: "2020-01-01T17:00:00Z",
            ageMin: 12,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/expired",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )

        let results = LocalOpportunitySnapshot.filter(
            [expired],
            query: "",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(LocalOpportunitySnapshot.isArchived(expired))
        XCTAssertTrue(LocalOpportunitySnapshot.hasPassed(expired.endDate))
    }

    func testClosedRegistrationDeadlineArchivesProgramBeforeItsEndDate() throws {
        let program = Opportunity(
            id: "closed-registration",
            title: "Closed summer program",
            organization: "Community Lab",
            description: "Enrollment has closed.",
            summary: nil,
            category: "Science & Engineering",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2026-07-06T08:00:00-04:00",
            endDate: "2026-08-28T15:00:00-04:00",
            deadline: "2026-07-01T23:59:00-04:00",
            ageMin: 12,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/closed-registration",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T16:00:00Z"))

        XCTAssertTrue(LocalOpportunitySnapshot.hasDistinctRegistrationDeadline(program))
        XCTAssertFalse(LocalOpportunitySnapshot.isCurrentlyAvailable(program, on: now))
    }

    func testMirroredStartDeadlineKeepsOngoingDropInAvailable() throws {
        let dropIn = Opportunity(
            id: "ongoing-drop-in",
            title: "Summer reading drop-in",
            organization: "Community Library",
            description: "An ongoing activity.",
            summary: nil,
            category: "STEM",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2026-06-20T04:00:00Z",
            endDate: "2026-09-01T03:59:59Z",
            deadline: "2026-06-20T04:00:00Z",
            ageMin: 6,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/ongoing-drop-in",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-06T16:00:00Z"))

        XCTAssertFalse(LocalOpportunitySnapshot.hasDistinctRegistrationDeadline(dropIn))
        XCTAssertTrue(LocalOpportunitySnapshot.isCurrentlyAvailable(dropIn, on: now))
    }

    func testSoonestSortHandlesFractionalSecondDates() {
        let first = Opportunity(
            id: "fractional-first",
            title: "First",
            organization: "Community Lab",
            description: "Sooner.",
            summary: nil,
            category: "Science & Engineering",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2099-01-01T10:00:00.000Z",
            endDate: nil,
            deadline: nil,
            ageMin: 12,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/first",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )
        let second = Opportunity(
            id: "standard-second",
            title: "Second",
            organization: "Community Lab",
            description: "Later.",
            summary: nil,
            category: "Science & Engineering",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: "2099-01-02T10:00:00Z",
            endDate: nil,
            deadline: nil,
            ageMin: 12,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com/second",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )

        let results = LocalOpportunitySnapshot.filter(
            [second, first],
            query: "",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["fractional-first", "standard-second"])
    }

    private func makeURLSessionForStub() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try makeInMemoryContainer())
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            OpportunityCacheRecord.self,
            SavedHuntRecord.self,
            SeenOpportunityRecord.self,
            SavedOpportunityRecord.self
        ])
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func approvedProviderFixture(_ opportunity: Opportunity) -> Opportunity {
        let host = URL(string: opportunity.sourceUrl)?.host?.lowercased()
        if (opportunity.organization == "Markham Public Library" && host == "markham.bibliocommons.com") ||
            (opportunity.organization == "Toronto Public Library" && host == "tpl.bibliocommons.com") {
            return opportunity
        }

        let sourceURL = "https://markham.bibliocommons.com/events/\(opportunity.id)"
        return Opportunity(
            id: opportunity.id,
            title: opportunity.title,
            organization: "Markham Public Library",
            description: opportunity.description,
            summary: opportunity.summary,
            category: opportunity.category,
            city: opportunity.city,
            region: opportunity.region,
            address: opportunity.address,
            latitude: opportunity.latitude,
            longitude: opportunity.longitude,
            startDate: opportunity.startDate,
            endDate: opportunity.endDate,
            deadline: opportunity.deadline,
            ageMin: opportunity.ageMin,
            ageMax: opportunity.ageMax,
            language: opportunity.language,
            cost: opportunity.cost,
            sourceUrl: sourceURL,
            registrationUrl: sourceURL,
            status: opportunity.status,
            volunteerHoursEligible: opportunity.volunteerHoursEligible,
            coopEligible: opportunity.coopEligible,
            tags: opportunity.tags,
            distanceKm: opportunity.distanceKm,
            isNewFind: opportunity.isNewFind,
            sourceConfidence: opportunity.sourceConfidence,
            translations: opportunity.translations
        )
    }

    private func makeOpportunitiesJSON(
        _ opportunities: [Opportunity],
        lastUpdated: Date = .now
    ) -> String {
        // Network fixtures must satisfy the same production rights manifest as
        // a Release build. Preserve already-approved bundled records and map
        // synthetic store scenarios onto a real approved provider contract.
        let approvedOpportunities = opportunities.map(approvedProviderFixture)
        let verifiedDate = DateFormatter()
        verifiedDate.locale = Locale(identifier: "en_US_POSIX")
        verifiedDate.timeZone = TimeZone(secondsFromGMT: 0)
        verifiedDate.dateFormat = "yyyy-MM-dd"
        let verifiedAt = verifiedDate.string(from: lastUpdated)
        let groupedSources = Dictionary(grouping: approvedOpportunities) { opportunity in
            let host = URL(string: opportunity.sourceUrl)?.host?.lowercased() ?? "example.com"
            return "\(opportunity.organization)\u{001F}\(host)"
        }
        let rightsSources = groupedSources.values.compactMap { group -> OpportunityListResponse.ContentRights.Source? in
            guard let opportunity = group.first,
                  let host = URL(string: opportunity.sourceUrl)?.host?.lowercased()
            else {
                return nil
            }
            let evidence: (basisURL: String, digest: String)
            switch (opportunity.organization, host) {
            case ("Markham Public Library", "markham.bibliocommons.com"):
                evidence = (
                    "https://markham.bibliocommons.com/info/terms/",
                    "sha256:451e63466c801166653f47336e236d05f9a50a3df45a917fa603e92bcd11c8a0"
                )
            case ("Toronto Public Library", "tpl.bibliocommons.com"):
                evidence = (
                    "https://tpl.bibliocommons.com/info/terms/",
                    "sha256:c9b14cbd531afa09533e844274bb9f07f8042883e12b5a3990be3100ca5d4b43"
                )
            default:
                return nil
            }
            return OpportunityListResponse.ContentRights.Source(
                organization: opportunity.organization,
                sourceHost: host,
                records: group.count,
                status: "terms-permitted",
                basisUrl: evidence.basisURL,
                conditions: [
                    "Automated access uses the provider's RSS/XML event feed.",
                    "Every displayed extract links to its original BiblioCommons event page.",
                    "GTA FREE STEM is free and does not monetize provider content."
                ],
                termsVerifiedAt: verifiedAt,
                termsVersion: "2018-09-19",
                termsDigestVersion: "bibliocommons-relevant-sections-v1",
                termsSectionDigest: evidence.digest
            )
        }
        let response = OpportunityListResponse(
            data: approvedOpportunities,
            meta: OpportunityListResponse.Metadata(
                activeCount: approvedOpportunities.count,
                lastUpdated: ISO8601DateFormatter().string(from: lastUpdated)
            ),
            sourceHealth: OpportunityListResponse.SourceHealth(
                library: .init(
                    status: "healthy",
                    attemptedPages: 1,
                    successfulPages: 1,
                    pageSuccessRatio: 1,
                    minimumPageSuccessRatio: 0.75,
                    acceptedListings: approvedOpportunities.count,
                    minimumAcceptedListings: min(1, approvedOpportunities.count)
                ),
                discovery: .init(
                    status: "healthy",
                    sourcesChecked: 1,
                    successfulSources: 1,
                    sourceSuccessRatio: 1,
                    minimumSourceSuccessRatio: 0.75
                )
            ),
            contentRights: OpportunityListResponse.ContentRights(
                termsVerifiedAt: verifiedAt,
                sources: rightsSources,
                restrictedOpportunityIDs: []
            ),
            publicationRevision: {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter.string(from: lastUpdated)
            }()
        )
        let encoder = JSONEncoder()
        let data = try! encoder.encode(response)
        return String(decoding: data, as: UTF8.self)
    }

    private func opportunity(
        id: String,
        title: String,
        organization: String,
        summary: String? = nil,
        category: String,
        city: String,
        address: String? = nil,
        status: String = "active",
        ageMin: Int = 10,
        ageMax: Int? = 18,
        volunteerHoursEligible: Bool = false,
        coopEligible: Bool = false,
        tags: [String] = []
    ) -> Opportunity {
        Opportunity(
            id: id,
            title: title,
            organization: organization,
            description: summary ?? title,
            summary: summary,
            category: category,
            city: city,
            region: "Toronto",
            address: address,
            latitude: nil,
            longitude: nil,
            startDate: nil,
            endDate: nil,
            deadline: nil,
            ageMin: ageMin,
            ageMax: ageMax,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com",
            registrationUrl: "https://example.com",
            status: status,
            volunteerHoursEligible: volunteerHoursEligible,
            coopEligible: coopEligible,
            tags: tags,
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil,
            translations: [:]
        )
    }
}

private actor NewMatchNotificationDeliveryStub: NewMatchNotificationDelivering {
    private var outcomes: [Bool]
    private var deliveredCount = 0

    init(outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func deliverNewMatchNotification(title: String, body: String) async -> Bool {
        deliveredCount += 1
        guard !outcomes.isEmpty else { return false }
        return outcomes.removeFirst()
    }

    func deliveryCount() -> Int {
        deliveredCount
    }
}

final class URLProtocolStub: URLProtocol {
    struct Response {
        let statusCode: Int
        let chunks: [Data]
        let delaySeconds: TimeInterval
        let errorCode: URLError.Code?
        let headers: [String: String]
        let finalResponseURL: URL?
        let holdResponse: Bool
        let holdBody: Bool
        let holdCompletion: Bool
    }

    private final class State: @unchecked Sendable {
        private var responses = [String: Response]()
        private var requests = [String: Int]()
        private var bytes = [String: Int]()
        private var stops = [String: Int]()
        private var finished = Set<String>()
        private var heldActions = [String: [DispatchWorkItem]]()
        private var releasedStages = Set<String>()
        private let lock = NSLock()

        func register(_ response: Response, for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            responses[url.absoluteString] = response
            releasedStages = Set(releasedStages.filter { !$0.hasPrefix(url.absoluteString + "#") })
        }

        func reset() {
            lock.lock()
            let pending = heldActions.values.flatMap { $0 }
            responses.removeAll()
            requests.removeAll()
            bytes.removeAll()
            stops.removeAll()
            finished.removeAll()
            heldActions.removeAll()
            releasedStages.removeAll()
            lock.unlock()
            pending.forEach { $0.cancel() }
        }

        func takeResponse(for url: URL) -> Response? {
            lock.lock()
            defer { lock.unlock() }
            requests[url.absoluteString, default: 0] += 1
            return responses[url.absoluteString]
        }

        func requestCount(for url: URL? = nil) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return url.map { requests[$0.absoluteString, default: 0] } ?? requests.values.reduce(0, +)
        }

        func recordBytes(_ count: Int, for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            bytes[url.absoluteString, default: 0] += count
        }

        func deliveredBytes(for url: URL) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return bytes[url.absoluteString, default: 0]
        }

        func recordStop(for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            stops[url.absoluteString, default: 0] += 1
        }

        func stopCount(for url: URL) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return stops[url.absoluteString, default: 0]
        }

        func recordFinish(for url: URL) {
            lock.lock()
            defer { lock.unlock() }
            finished.insert(url.absoluteString)
        }

        func didFinish(for url: URL) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished.contains(url.absoluteString)
        }

        func hold(_ action: DispatchWorkItem, for url: URL, stage: String) {
            lock.lock()
            let key = url.absoluteString + "#" + stage
            if releasedStages.contains(key) {
                lock.unlock()
                action.perform()
            } else {
                heldActions[key, default: []].append(action)
                lock.unlock()
            }
        }

        func release(for url: URL, stage: String) {
            lock.lock()
            let key = url.absoluteString + "#" + stage
            releasedStages.insert(key)
            let actions = heldActions.removeValue(forKey: key) ?? []
            lock.unlock()
            actions.forEach { $0.perform() }
        }
    }

    private static let state = State()
    private let pendingLock = NSLock()
    private var pendingWorkItems = [DispatchWorkItem]()
    private var stopped = false

    static var requestCount: Int { state.requestCount() }
    static func requestCount(for url: URL) -> Int { state.requestCount(for: url) }
    static func deliveredBytes(for url: URL) -> Int { state.deliveredBytes(for: url) }
    static func stopCount(for url: URL) -> Int { state.stopCount(for: url) }
    static func didFinish(for url: URL) -> Bool { state.didFinish(for: url) }
    static func releaseResponse(for url: URL) { state.release(for: url, stage: "response") }
    static func releaseBody(for url: URL) { state.release(for: url, stage: "body") }
    static func releaseCompletion(for url: URL) { state.release(for: url, stage: "completion") }

    static func register(
        responseFor url: URL,
        statusCode: Int,
        body: Data,
        delaySeconds: TimeInterval = 0,
        headers: [String: String] = [:],
        finalResponseURL: URL? = nil,
        holdBody: Bool = false,
        holdResponse: Bool = false
    ) {
        state.register(Response(
            statusCode: statusCode, chunks: [body], delaySeconds: delaySeconds,
            errorCode: nil, headers: headers, finalResponseURL: finalResponseURL,
            holdResponse: holdResponse, holdBody: holdBody, holdCompletion: false
        ), for: url)
    }

    static func register(responseFor url: URL, errorCode: URLError.Code, delaySeconds: TimeInterval = 0, holdResponse: Bool = false) {
        state.register(Response(
            statusCode: 0, chunks: [], delaySeconds: delaySeconds,
            errorCode: errorCode, headers: [:], finalResponseURL: nil,
            holdResponse: holdResponse, holdBody: false, holdCompletion: false
        ), for: url)
    }

    static func register(responseFor url: URL, chunks: [Data], holdCompletion: Bool = false) {
        state.register(Response(
            statusCode: 200, chunks: chunks, delaySeconds: 0,
            errorCode: nil, headers: [:], finalResponseURL: nil,
            holdResponse: false, holdBody: false, holdCompletion: holdCompletion
        ), for: url)
    }

    static func reset() { state.reset() }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "https" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool { a == b }

    private var hasStopped: Bool {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return stopped
    }

    private func enqueue(_ action: DispatchWorkItem, for url: URL, heldStage: String? = nil, delay: TimeInterval = 0) {
        pendingLock.lock()
        guard !stopped else {
            pendingLock.unlock()
            action.cancel()
            return
        }
        pendingWorkItems.append(action)
        pendingLock.unlock()
        if let heldStage {
            Self.state.hold(action, for: url, stage: heldStage)
        } else if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: action)
        } else {
            action.perform()
        }
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.state.takeResponse(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let action = DispatchWorkItem { [weak self] in
            guard let self, !self.hasStopped else { return }
            if let errorCode = stub.errorCode {
                self.client?.urlProtocol(self, didFailWithError: URLError(errorCode))
                return
            }
            guard let response = HTTPURLResponse(
                url: stub.finalResponseURL ?? url, statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1", headerFields: stub.headers
            ) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let body = DispatchWorkItem { [weak self] in
                guard let self, !self.hasStopped else { return }
                for chunk in stub.chunks {
                    guard !self.hasStopped else { return }
                    Self.state.recordBytes(chunk.count, for: url)
                    self.client?.urlProtocol(self, didLoad: chunk)
                }
                let finish = DispatchWorkItem { [weak self] in
                    guard let self, !self.hasStopped else { return }
                    Self.state.recordFinish(for: url)
                    self.client?.urlProtocolDidFinishLoading(self)
                }
                self.enqueue(finish, for: url, heldStage: stub.holdCompletion ? "completion" : nil)
            }
            self.enqueue(body, for: url, heldStage: stub.holdBody ? "body" : nil)
        }
        enqueue(action, for: url, heldStage: stub.holdResponse ? "response" : nil, delay: stub.delaySeconds)
    }

    override func stopLoading() {
        pendingLock.lock()
        guard !stopped else { pendingLock.unlock(); return }
        stopped = true
        let pending = pendingWorkItems
        pendingWorkItems.removeAll()
        pendingLock.unlock()
        pending.forEach { $0.cancel() }
        if let url = request.url { Self.state.recordStop(for: url) }
    }
}

private actor APIRequestStartGate {
    private var released = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
