import XCTest
@testable import GTAFreeSTEM
import SwiftData

final class APIClientTests: XCTestCase {
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift"))
        let buttonStart = try XCTUnwrap(source.range(of: "private var signOutButton"))
        let buttonEnd = try XCTUnwrap(source.range(of: "private var deleteAccountButton", range: buttonStart.lowerBound..<source.endIndex))
        let clearButtonSource = String(source[buttonStart.lowerBound..<buttonEnd.lowerBound])

        XCTAssertTrue(clearButtonSource.contains("clearLocalProfileOnly()"))
        XCTAssertFalse(clearButtonSource.contains("clearLocalProfileAndSaves()"))
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
            storeSource.contains("guard let cached = await Self.decodeCachedFullResponse(payload)"),
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
        XCTAssertFalse(
            AppLaunchConfiguration.isScreenshotCapture(
                environment: [AppLaunchConfiguration.screenshotModeEnvironmentKey: "0"]
            )
        )
    }

    @MainActor
    func testScreenshotSnapshotUsesBundledFeedWithoutStartingNetwork() async {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }

        let feedURL = URL(string: "https://example.com/opportunities.json")!
        let client = APIClient(feedURL: feedURL, session: makeURLSessionForStub())
        let store = OpportunityStore(api: client)
        store.query = "robotics"

        let isReady = await store.prepareScreenshotSnapshot()

        XCTAssertTrue(isReady)
        XCTAssertFalse(store.opportunities.isEmpty)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
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
        let payload = try JSONEncoder().encode(
            OpportunityListResponse(
                data: [opportunity(id: "production-sized", title: "Production Feed", description: largeDescription)],
                meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: currentFeedTimestamp()),
                sourceHealth: sourceHealth(publishedCount: 1)
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let watchSource = try String(contentsOf: repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift"))

        XCTAssertTrue(watchSource.contains("savedEventsPayload"))
        XCTAssertTrue(watchSource.contains("requestSavedEvents"))
        XCTAssertTrue(watchSource.contains("watch-saved-events-v1"))
        XCTAssertTrue(watchSource.contains("session.receivedApplicationContext"))
        XCTAssertTrue(watchSource.contains("lastSyncedAt = envelope.syncedAt"))
        XCTAssertTrue(watchSource.contains("Still showing the latest events saved on this watch."))
        XCTAssertTrue(watchSource.contains("let archiveBoundary: Date?"))
        XCTAssertTrue(watchSource.contains("if archived == true { return true }"))
        XCTAssertTrue(
            watchSource.contains("TimeZone(identifier: \"America/Toronto\")"),
            "Date-only GTA events must retain their declared calendar day on Watch."
        )
        XCTAssertFalse(watchSource.contains("expiryDate(from: startDate)"))
        XCTAssertFalse(watchSource.contains("URLSession"), "The Watch companion must use the paired iPhone's saved-event sync rather than its own public network feed.")
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

    func testReleaseSourceContainsNoDormantAccountOrLegacyWatchFeedState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
            (AppLegalLinks.privacyPolicy, "https://gta-free-stem.vercel.app/privacy/"),
            (AppLegalLinks.termsOfUse, "https://gta-free-stem.vercel.app/terms/"),
            (AppLegalLinks.support, "https://gta-free-stem.vercel.app/support/")
        ]

        XCTAssertEqual(Set(expected.map(\.0)).count, expected.count)
        for (url, absoluteString) in expected {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "gta-free-stem.vercel.app")
            XCTAssertEqual(url.absoluteString, absoluteString)
        }
    }

    func testSupportViewDoesNotCollectOrPersistSubmissionPersonalData() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let submitView = repoRoot.appendingPathComponent("GTAFreeSTEM/SubmitView.swift")
        let contents = try String(contentsOf: submitView)

        XCTAssertFalse(contents.contains("TextField("), "Release support view should not collect name, email, feedback, or submission text while App Privacy says no collected user data.")
        XCTAssertFalse(contents.contains("previewSubmissions"), "Release support view must not store personal submission drafts in UserDefaults.")
        XCTAssertFalse(contents.contains("UserDefaults.standard.set"), "Release support view must not persist personal support data locally.")
        XCTAssertFalse(contents.contains("sendFeedback("), "Release support view should not transmit feedback until backend privacy handling is live.")
        XCTAssertFalse(contents.contains("submitMissingOpportunity("), "Release support view should not transmit missing-opportunity submissions until backend privacy handling is live.")
    }

    func testReleaseAPIClientContainsOnlyReadOnlyFeedRequests() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"))
        let entitlementsURL = repoRoot.appendingPathComponent("GTAFreeSTEM/MacCatalyst.entitlements")
        let infoURL = repoRoot.appendingPathComponent("GTAFreeSTEM/MacCatalyst-Info.plist")

        XCTAssertTrue(project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\": GTAFreeSTEM/MacCatalyst.entitlements"))
        XCTAssertTrue(project.contains("\"ENABLE_APP_SANDBOX[sdk=macosx*]\": \"YES\""))
        XCTAssertTrue(project.contains("\"ENABLE_HARDENED_RUNTIME[sdk=macosx*]\": \"YES\""))
        XCTAssertEqual(
            project.components(separatedBy: "CODE_SIGN_IDENTITY: Apple Distribution").count - 1,
            2,
            "The iOS/Mac app and Watch companion must request Apple Distribution signing for Release."
        )

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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let watchApp = repoRoot.appendingPathComponent("GTAFreeSTEMWatch/GTAFreeSTEMWatchApp.swift")
        let contents = try String(contentsOf: watchApp)

        XCTAssertTrue(contents.contains("Saved events"))
        XCTAssertTrue(contents.contains("Event archive"))
        XCTAssertTrue(contents.contains("Your past saved events are still available in the archive."))
        XCTAssertTrue(contents.contains("Showing \\(store.events.count) of \\(store.totalSavedCount) saved events"))
        XCTAssertTrue(contents.contains("Open GTA FREE STEM on your iPhone to refresh saved events."))
    }

    func testCompactBrowseLayoutPrioritizesLiveResults() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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

    func testOpportunitiesApplyBundledTranslationFallbackToSearch() async throws {
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
        let client = APIClient(feedURL: feedURL, session: session)

        let liveOnly = """
        {
          "lastDataChange": "\(currentFeedTimestamp())",
          "sourceHealth": {
            "library": {
              "status": "healthy",
              "attemptedPages": 1,
              "successfulPages": 1,
              "pageSuccessRatio": 1,
              "minimumPageSuccessRatio": 0.75,
              "acceptedListings": 1,
              "minimumAcceptedListings": 1
            },
            "discovery": {
              "status": "healthy",
              "sourcesChecked": 1,
              "successfulSources": 1,
              "sourceSuccessRatio": 1,
              "minimumSourceSuccessRatio": 0.75
            }
          },
          "opportunities": [{
            "id": "cvc-conservation-youth-corps-2026",
            "title": "Conservation Volunteer Day",
            "organization": "Credit Valley Conservation",
            "description": "Volunteer in support of conservation projects.",
            "category": "Volunteer Hours",
            "city": "Mississauga",
            "region": "Peel",
            "ageMin": 14,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com/cvc",
            "status": "active",
            "volunteerHoursEligible": true,
            "coopEligible": false,
            "tags": ["volunteer"],
            "sourceConfidence": "generated"
          }]
        }
        """

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: liveOnly.data(using: .utf8)!
        )

        let response = try await client.opportunities(query: "benevolat", mode: .all, filters: OpportunityFilters())

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "cvc-conservation-youth-corps-2026")
        XCTAssertEqual(
            response.data.first?.localizedSummary(language: .fr),
            "Occasion gratuite de Heures de benevolat offerte par Credit Valley Conservation a Mississauga. Ages 14-18. Consultez la source pour les details."
        )
        XCTAssertEqual(response.data.first?.localizedCategory(language: .fr), "Heures de benevolat")
    }

    func testLocalOpportunitySnapshotFiltersByLanguage() throws {
        var filters = OpportunityFilters()
        filters.language = "en"

        let response = try LocalOpportunitySnapshot.load(query: "", mode: .all, filters: filters)

        XCTAssertFalse(response.data.isEmpty)
        XCTAssertTrue(response.data.allSatisfy { $0.language.contains("en") })
        XCTAssertEqual(response.meta?.activeCount, response.data.count)
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
                opportunity(id: "open-adult", title: "Adult Makerspace", ageMin: 21, ageMax: nil)
            ],
            query: "",
            mode: .all,
            filters: filters
        )

        XCTAssertEqual(Set(results.map(\.id)), Set(["adult-range", "open-adult"]))
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let browseView = repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift")
        let contents = try String(contentsOf: browseView)

        XCTAssertTrue(
            contents.contains(".accessibilityHint(session.text(\"openDetailsHint\"))"),
            "Opportunity rows should expose a localized VoiceOver hint for opening detail pages."
        )
    }

    func testMapExposesLocalizedVisibleResultCountForVoiceOver() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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

    func testBackgroundRefreshUsesCacheContextAndNewMatchNotifications() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appFile = repoRoot.appendingPathComponent("GTAFreeSTEM/GTAFreeSTEMApp.swift")
        let appContents = try String(contentsOf: appFile)

        XCTAssertTrue(appContents.contains(".backgroundTask(.appRefresh(Self.appRefreshIdentifier))"))
        XCTAssertTrue(appContents.contains("let context = ModelContext(Self.sharedModelContainer)"))
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        translations: [String: OpportunityTranslation] = [:]
    ) -> Opportunity {
        Opportunity(
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
            sourceUrl: "https://example.com/\(id)",
            registrationUrl: nil,
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

    private func encodedFeed(id: String, lastUpdated: String?) throws -> Data {
        try encodedFeed(ids: [id], lastUpdated: lastUpdated)
    }

    private func encodedFeed(
        ids: [String],
        lastUpdated: String?,
        sourceHealthStatus: String = "healthy",
        minimumAcceptedListings: Int = 1
    ) throws -> Data {
        try JSONEncoder().encode(
            OpportunityListResponse(
                data: ids.map { opportunity(id: $0, title: $0) },
                meta: OpportunityListResponse.Metadata(activeCount: ids.count, lastUpdated: lastUpdated),
                sourceHealth: sourceHealth(
                    publishedCount: ids.count,
                    status: sourceHealthStatus,
                    minimumAcceptedListings: minimumAcceptedListings
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

        let store = OpportunityStore(api: APIClient())
        let prepared = await store.prepareInitialSnapshot(cache: context)

        XCTAssertTrue(prepared)
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
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
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
                lastUpdated: ISO8601DateFormatter().string(from: .now)
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
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let context = try makeInMemoryContext()

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
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: "2026-08-06")
        )
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: try JSONEncoder().encode(cached)))
        try context.save()

        let emptyPayload = """
        {"count":0,"lastDataChange":"\(ISO8601DateFormatter().string(from: .now))","opportunities":[]}
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
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
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
            body: Data(makeOpportunitiesJSON([live]).utf8),
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
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let store = OpportunityStore(api: APIClient(feedURL: feedURL, session: session))

        let prepared = await store.prepareInitialSnapshot(cache: nil)

        XCTAssertTrue(prepared)
        XCTAssertGreaterThan(store.opportunities.count, 0)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertEqual(store.huntPhase, .cached)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(URLProtocolStub.requestCount, 0)
    }

    @MainActor
    func testSearchUsesBundledFullFeedWhileLiveRefreshIsInFlight() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let bundledFeed = try LocalOpportunitySnapshot.loadFull()
        let initiallyVisible = LocalOpportunitySnapshot.filter(
            bundledFeed.data,
            query: "",
            mode: .all,
            filters: OpportunityFilters()
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
            body: Data(makeOpportunitiesJSON([live]).utf8),
            delaySeconds: 0.70
        )

        // This matches the real launch contract: GTAFreeSTEMApp prepares the
        // snapshot before ContentView starts its background live refresh.
        let prepared = await store.prepareInitialSnapshot(cache: nil)
        XCTAssertTrue(prepared)
        XCTAssertGreaterThan(store.opportunities.count, 0)

        let liveRefresh = Task { @MainActor in
            await store.refresh(cache: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.isLoading)

        store.query = searchableOpportunity.title
        let expectedIDs = LocalOpportunitySnapshot.filter(
            bundledFeed.data,
            query: store.query,
            mode: store.mode,
            filters: store.filters
        ).map(\.id)
        await store.refresh(cache: nil)

        XCTAssertEqual(store.opportunities.map(\.id), expectedIDs)
        XCTAssertEqual(store.dataSourceLabel, .previewDatabase)
        XCTAssertTrue(store.isLoading)

        await liveRefresh.value
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testRefreshFallsBackToBundledSnapshotWithoutCache() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

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
                    registrationUrl: nil,
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            OpportunityCacheRecord.self,
            SavedHuntRecord.self,
            SeenOpportunityRecord.self,
            SavedOpportunityRecord.self
        ])
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    private func makeOpportunitiesJSON(_ opportunities: [Opportunity]) -> String {
        let response = OpportunityListResponse(
            data: opportunities,
            meta: OpportunityListResponse.Metadata(
                activeCount: opportunities.count,
                lastUpdated: ISO8601DateFormatter().string(from: .now)
            ),
            sourceHealth: OpportunityListResponse.SourceHealth(
                library: .init(
                    status: "healthy",
                    attemptedPages: 1,
                    successfulPages: 1,
                    pageSuccessRatio: 1,
                    minimumPageSuccessRatio: 0.75,
                    acceptedListings: opportunities.count,
                    minimumAcceptedListings: min(1, opportunities.count)
                ),
                discovery: .init(
                    status: "healthy",
                    sourcesChecked: 1,
                    successfulSources: 1,
                    sourceSuccessRatio: 1,
                    minimumSourceSuccessRatio: 0.75
                )
            )
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
        status: String = "active"
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
            ageMin: 10,
            ageMax: 18,
            language: ["en"],
            cost: "Free",
            sourceUrl: "https://example.com",
            registrationUrl: nil,
            status: status,
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil,
            translations: [:]
        )
    }
}

final class URLProtocolStub: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
        let delaySeconds: TimeInterval
    }

    private final class State: @unchecked Sendable {
        private var responses = [String: Response]()
        private var requestCount = 0
        private let lock = NSLock()

        func register(responseFor url: URL, statusCode: Int, body: Data, delaySeconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            responses[url.absoluteString] = Response(statusCode: statusCode, body: body, delaySeconds: delaySeconds)
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            responses.removeAll()
            requestCount = 0
        }

        func takeResponse(for url: URL) -> Response? {
            lock.lock()
            defer { lock.unlock() }
            requestCount += 1
            return responses[url.absoluteString]
        }

        func currentRequestCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCount
        }
    }

    private static let state = State()

    static var requestCount: Int {
        state.currentRequestCount()
    }

    static func register(responseFor url: URL, statusCode: Int, body: Data, delaySeconds: TimeInterval = 0.0) {
        state.register(responseFor: url, statusCode: statusCode, body: body, delaySeconds: delaySeconds)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return a == b
    }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.state.takeResponse(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)
        let body = stub.body
        let delay = stub.delaySeconds

        let action = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: action)
        } else {
            action.perform()
        }
    }

    override func stopLoading() {}
}
