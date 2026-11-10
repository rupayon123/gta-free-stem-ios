import CoreLocation
import Foundation
import SwiftData
@preconcurrency import UserNotifications

enum HuntPhase: Equatable {
    case idle
    case hunting
    case fresh
    case cached
    case offline

    var icon: String {
        switch self {
        case .idle: "sparkle.magnifyingglass"
        case .hunting: "sparkle.magnifyingglass"
        case .fresh: "checkmark.seal.fill"
        case .cached: "sparkle.magnifyingglass"
        case .offline: "sparkle.magnifyingglass"
        }
    }

    var titleKey: String {
        switch self {
        case .idle: "readyToHunt"
        case .hunting: "huntingNow"
        case .fresh: "freshResultsLoaded"
        case .cached: "showingSavedResults"
        case .offline: "offlinePreview"
        }
    }
}

enum OpportunityFeedSelection {
    /// A live response must never move retained data backwards. A missing
    /// candidate date is also older than a retained feed with a declared date;
    /// legacy equal dates allow corrections; known revisions must advance.
    static func isOlder(_ candidate: OpportunityListResponse, than retained: OpportunityListResponse?, now: Date = .now) -> Bool {
        guard candidate.hasValidPublicationRevision(now: now) else { return true }
        guard let retained, retained.hasValidPublicationRevision(now: now) else { return false }
        if let retainedRevision = FeedPublicationRevision.date(from: retained.publicationRevision) {
            guard let candidateRevision = FeedPublicationRevision.date(from: candidate.publicationRevision),
                  candidateRevision > retainedRevision else { return true }
        }
        let candidateDate = FeedFreshness.date(from: candidate.meta?.lastUpdated)
        let retainedDate = FeedFreshness.date(from: retained.meta?.lastUpdated)
        switch (candidateDate, retainedDate) {
        case let (.some(candidateDate), .some(retainedDate)):
            return candidateDate < retainedDate
        case (.none, .some):
            return true
        case (.some, .none), (.none, .none):
            return false
        }
    }

    /// Returns true when a candidate retained feed is more useful or newer than
    /// the currently selected one. Equal dates keep the existing source so a
    /// validated live cache is not replaced unnecessarily by bundled data.
    static func shouldPrefer(_ candidate: OpportunityListResponse, over retained: OpportunityListResponse?, now: Date = .now) -> Bool {
        guard candidate.hasValidPublicationRevision(now: now) else { return false }
        let candidateIsUsable = !candidate.data.isEmpty || candidate.meta?.lastUpdated != nil
        guard candidateIsUsable else { return false }
        guard let retained, retained.hasValidPublicationRevision(now: now) else { return true }
        let candidateRevision = FeedPublicationRevision.date(from: candidate.publicationRevision)
        let retainedRevision = FeedPublicationRevision.date(from: retained.publicationRevision)
        if let retainedRevision {
            guard let candidateRevision, candidateRevision > retainedRevision else { return false }
        }

        let retainedIsUsable = !retained.data.isEmpty || retained.meta?.lastUpdated != nil
        guard retainedIsUsable else { return true }

        let candidateDate = FeedFreshness.date(from: candidate.meta?.lastUpdated)
        let retainedDate = FeedFreshness.date(from: retained.meta?.lastUpdated)
        switch (candidateDate, retainedDate) {
        case let (.some(candidateDate), .some(retainedDate)):
            return candidateDate > retainedDate || (candidateDate == retainedDate && candidateRevision != nil)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return retained.data.isEmpty && !candidate.data.isEmpty
        }
    }
}

enum KnownOpportunityHistory {
    static let maximumCount = 2_500

    static func merging(
        currentIDs: [String],
        previousIDs: [String],
        countingIDs: [String]? = nil,
        limit: Int = maximumCount
    ) -> (retainedIDs: [String], newCount: Int) {
        let normalizedLimit = max(0, limit)
        let current = unique(currentIDs)
        let currentSet = Set(current)
        let previous = unique(previousIDs)
        let previousSet = Set(previous)
        let idsToCount = unique(countingIDs ?? current).filter(currentSet.contains)
        let newCount = idsToCount.reduce(into: 0) { count, id in
            if !previousSet.contains(id) { count += 1 }
        }

        guard normalizedLimit > 0 else { return ([], newCount) }
        var retained = Array(current.prefix(normalizedLimit))
        var retainedSet = Set(retained)
        for id in previous where retained.count < normalizedLimit && !retainedSet.contains(id) {
            retained.append(id)
            retainedSet.insert(id)
        }
        return (retained, newCount)
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

enum HomePathwayInventory {
    static let promotedModes: [SearchMode] = [.volunteer, .coop, .mentorship]

    /// Uses the same filtering path as Browse so a Home promotion can never
    /// promise a pathway that opens to zero current, eligible records.
    static func availableModes(
        in opportunities: [Opportunity],
        now: Date = .now
    ) -> [SearchMode] {
        promotedModes.filter { mode in
            !LocalOpportunitySnapshot.filter(
                opportunities,
                query: "",
                mode: mode,
                filters: OpportunityFilters(),
                now: now
            ).isEmpty
        }
    }
}

protocol NewMatchNotificationDelivering: Sendable {
    /// Returns true only after the system accepts an authorized notification request.
    func deliverNewMatchNotification(title: String, body: String) async -> Bool
}

struct SystemNewMatchNotificationDelivery: NewMatchNotificationDelivering {
    func deliverNewMatchNotification(title: String, body: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "new-opportunities-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}

// Preferences live separately from saved criteria so v1 saved-filter archives
// continue to decode unchanged. Nothing here is uploaded to a server.
struct SavedFilterAlertState: Codable, Equatable, Sendable {
    var acknowledgedIDs: Set<String>
    var hasBaseline: Bool
}

struct OpportunityNotificationPreferences: Codable, Equatable, Sendable {
    var version = 1
    var dailyEnabled = false
    var hour = 9
    var minute = 0
    var filters: [String: SavedFilterAlertState] = [:]

    var isValid: Bool {
        version == 1 && (0..<24).contains(hour) && (0..<60).contains(minute)
            && filters.count <= 16 && filters.allSatisfy {
                UUID(uuidString: $0.key) != nil && $0.value.acknowledgedIDs.count <= 20_000
            }
    }
}

protocol OpportunityNotificationScheduling: Sendable {
    func requestPermission() async -> Bool
    func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async -> Bool
    func cancelDaily() async
}

struct SystemOpportunityNotificationScheduler: OpportunityNotificationScheduling {
    static let dailyIdentifier = "gta-daily-discovery-reminder"

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
    }

    func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async -> Bool {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        guard let request = Self.dailyRequest(hour: hour, minute: minute, title: title, body: body) else { return false }
        do { try await center.add(request); return true } catch { return false }
    }

    static func dailyRequest(hour: Int, minute: Int, title: String, body: String) -> UNNotificationRequest? {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A repeating calendar request follows the phone's local time, including
        // daylight-saving changes. One stable ID replaces the previous schedule.
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        return UNNotificationRequest(identifier: Self.dailyIdentifier, content: content, trigger: trigger)
    }

    func cancelDaily() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.dailyIdentifier])
    }
}

@MainActor
final class OpportunityStore: ObservableObject {
    @Published var query = ""
    @Published var mode: SearchMode = .all
    @Published var filters = OpportunityFilters()
    @Published var opportunities: [Opportunity] = []
    @Published var activeCount = 0
    @Published var lastUpdated: String?
    @Published var dataSourceLabel: DataSource = .publicLiveFeed
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var huntPhase: HuntPhase = .idle
    @Published var lastHuntStartedAt: Date?
    @Published var lastSuccessfulHuntAt: Date?
    @Published var newMatchesCount = 0
    @Published private(set) var homeTopics: [String] = []
    @Published private(set) var savedSearches: [NamedSavedSearch] = []
    @Published private(set) var activeSavedSearchID: UUID?
    @Published var savedSearchError: String?
    static let namedSearchesKey = "namedSavedSearches.v1"
    private var namedSearchStorageReadable = true
    private var namedSearchGeneration = 0
    private var localPreviewGeneration = 0
#if DEBUG
    // Deterministic tests can suspend a worker at the commit boundary.
    var namedSearchReconciliationGate: (() async -> Void)?
    var localPreviewCommitGate: (() async -> Void)?
    var cacheEncodingCommitGate: (() async -> Void)?
#endif
    @Published private(set) var notificationPreferences = OpportunityNotificationPreferences()
    @Published private(set) var isUpdatingNotificationPreferences = false
    static let notificationPreferencesKey = "opportunityNotificationPreferences.v1"
    private var notificationPreferencesReadable = true
    private var notificationPreferenceGeneration = 0
    private var isDeliveringSavedFilterAlert = false
    private let notificationScheduler: any OpportunityNotificationScheduling
    @Published var notificationStatusMessage: String?
    @Published var didRestoreLastHunt = false
    @Published private(set) var availableHomePathwayModes: [SearchMode] = []
    @Published private(set) var availableFilterCities: [String] = []
    @Published private(set) var availableFilterCategories: [String] = []

    private let api: APIClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private let notificationDelivery: any NewMatchNotificationDelivering
    private let cacheKey = "latest-opportunities"
    private let huntKey = "last-hunt"
    private let knownIDsKey = "knownOpportunityIDs"
    private let lastNotificationKey = "lastNewOpportunityNotificationAt"
    private let minimumRefreshInterval: TimeInterval = 1.0
    private let foregroundRefreshInterval: TimeInterval = 60 * 15
    private let minimumNotificationInterval: TimeInterval = 60 * 60
    private let seenRecordRetentionInterval: TimeInterval = 60 * 60 * 24 * 120
    private let maximumCachePayloadBytes = 10_000_000
    private var lastNotificationSentAt: Date?
    private var lastRefreshStartedAt: Date?
    private var inMemoryFeed: OpportunityListResponse?
    private var catalogueGeneration = 0
    private var overlayInstallGeneration = 0
    private var overlayExpiryTask: Task<Void, Never>?
    private var retainedFeedSource: DataSource = .publicLiveFeed
    @Published private(set) var preparedListingOverlay: PreparedListingOverlay?
    @Published private(set) var retainedFeedSHA256: String?
    private var preparedSearchIndex: (generation: Int, language: AppLanguage, packSHA256: String?, values: [String: String])?

    /// Catalogue scans are CPU work. Keep them off the UI actor and publish
    /// their inventory only if this is still the retained feed on completion.
    @discardableResult
    private func retainFullFeed(_ response: OpportunityListResponse?, source: DataSource) async -> Int {
        catalogueGeneration &+= 1
        overlayInstallGeneration &+= 1
        overlayExpiryTask?.cancel()
        overlayExpiryTask = nil
        let generation = catalogueGeneration
        let preservedOverlay = preparedListingOverlay.flatMap { overlay in
            response?.sourceFeedBytes != nil && overlay.locale == AppLanguage.preferred() &&
                overlay.generatedAt <= now() && now() < overlay.expiresAt ? overlay : nil
        }
        inMemoryFeed = response
        preparedListingOverlay = preservedOverlay
        retainedFeedSHA256 = nil
        preparedSearchIndex = nil
        retainedFeedSource = source
        availableHomePathwayModes = []
        availableFilterCities = []
        availableFilterCategories = []
        homeTopics = []
        guard let response else { return generation }
        if let bytes = response.sourceFeedBytes {
            let digest = await Task.detached(priority: .utility) { FullDescriptionBinding.hashBytes(bytes) }.value
            guard generation == catalogueGeneration, !Task.isCancelled else { return generation }
            retainedFeedSHA256 = digest
            if let preservedOverlay { scheduleOverlayExpiry(preservedOverlay) }
        }
        let snapshotNow = now()
        let inventory = await Task.detached(priority: .userInitiated) {
            let modes = HomePathwayInventory.availableModes(in: response.data, now: snapshotNow)
            var cities = Set<String>()
            var categories = Set<String>()
            for opportunity in response.data {
                guard opportunity.isExplicitlyFree,
                      LocalOpportunitySnapshot.isCurrentlyAvailable(opportunity, on: snapshotNow)
                else { continue }
                if !opportunity.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cities.insert(opportunity.city)
                }
                if !opportunity.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    categories.insert(opportunity.category)
                }
            }
            return (modes: modes, cities: cities.sorted(), categories: categories.sorted())
        }.value
        guard generation == catalogueGeneration else { return generation }
        availableHomePathwayModes = inventory.modes
        availableFilterCities = inventory.cities
        availableFilterCategories = inventory.categories
        let preferred = ["Science & Engineering", "Coding & Robotics", "Makerspace & Fabrication", "Arts & Media", "Family Learning", "Career & Mentorship"]
        let ordered = preferred.filter(inventory.categories.contains) + inventory.categories.filter { !preferred.contains($0) }
        homeTopics = Array(ordered.prefix(6))
        return generation
    }

    /// No transport is provided here. The expected digest must come from a
    /// separately authenticated and approved publication, not the pack itself.
    @discardableResult
    func installPreparedOverlay(data: Data, expectedPackSHA256: String, locale: AppLanguage, pinnedSourceFeed: Data? = nil) async throws -> Bool {
        guard let feed = inMemoryFeed, let bytes = feed.sourceFeedBytes, let digest = retainedFeedSHA256,
              locale == AppLanguage.preferred() else { return false }
        let generation = catalogueGeneration
        overlayInstallGeneration &+= 1
        let installGeneration = overlayInstallGeneration
        let overlay = try await PreparedListingOverlay.validateOffMain(data: data, sourceFeedData: pinnedSourceFeed ?? bytes,
                                                                        locale: locale, expectedPackSHA256: expectedPackSHA256, now: now())
        guard !Task.isCancelled, generation == catalogueGeneration, installGeneration == overlayInstallGeneration, digest == retainedFeedSHA256,
              locale == AppLanguage.preferred() else { return false }
        if let retained = preparedListingOverlay {
            guard overlay.generatedAt >= retained.generatedAt,
                  overlay.generatedAt != retained.generatedAt || overlay.packSHA256 == retained.packSHA256 else { return false }
        }
        let snapshotQuery = query, snapshotMode = mode, snapshotFilters = filters, snapshotNow = now()
        let worker = Task.detached(priority: .userInitiated) {
            let index = LocalOpportunitySnapshot.prepareSearchIndex(feed.data, displayLanguage: locale, overlay: overlay, feedSHA256: digest, now: snapshotNow)
            let filtered = LocalOpportunitySnapshot.filter(feed.data, query: snapshotQuery, mode: snapshotMode, filters: snapshotFilters,
                displayLanguage: locale, now: snapshotNow, preparedSearchIndex: index, preparedOverlay: overlay, currentFeedSHA256: digest)
            return (index, filtered)
        }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, generation == catalogueGeneration, installGeneration == overlayInstallGeneration, digest == retainedFeedSHA256,
              locale == AppLanguage.preferred(), snapshotQuery == query, snapshotMode == mode, snapshotFilters == filters,
              now() < overlay.expiresAt else { return false }
        preparedListingOverlay = overlay
        preparedSearchIndex = (generation, locale, overlay.packSHA256, result.0)
        apply(OpportunityListResponse(data: result.1, meta: .init(activeCount: result.1.count, lastUpdated: feed.meta?.lastUpdated),
                                      publicationRevision: feed.publicationRevision), source: retainedFeedSource)
        scheduleOverlayExpiry(overlay)
        return true
    }

    private func scheduleOverlayExpiry(_ overlay: PreparedListingOverlay) {
        overlayExpiryTask?.cancel()
        let seconds = max(0, overlay.expiresAt.timeIntervalSince(now()))
        overlayExpiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            guard let self, self.preparedListingOverlay?.packSHA256 == overlay.packSHA256 else { return }
            if self.now() < overlay.expiresAt { self.scheduleOverlayExpiry(overlay); return }
            self.overlayExpiryTask = nil
            await self.reconcilePreparedOverlay()
        }
    }

    func reconcilePreparedOverlay() async {
        guard let overlay = preparedListingOverlay else { return }
        guard overlay.locale != AppLanguage.preferred() || retainedFeedSHA256 == nil ||
              now() < overlay.generatedAt || now() >= overlay.expiresAt else { return }
        overlayInstallGeneration &+= 1
        overlayExpiryTask?.cancel()
        overlayExpiryTask = nil
        preparedListingOverlay = nil
        preparedSearchIndex = nil
        guard let feed = inMemoryFeed else { return }
        let generation = catalogueGeneration
        let result = await responseForCurrentHunt(from: feed)
        guard !Task.isCancelled, generation == catalogueGeneration, preparedListingOverlay == nil else { return }
        apply(result, source: retainedFeedSource)
    }

    func preparedText(for opportunity: Opportunity, locale: AppLanguage) -> (title: String, description: String)? {
        guard let overlay = preparedListingOverlay, overlay.locale == locale, retainedFeedSHA256 != nil else { return nil }
        return overlay.resolve(opportunity, now: now())
    }

    func title(for opportunity: Opportunity, session: SessionStore) -> String {
        let providerText = opportunity.localizedTitle(language: session.language)
        if !providerText.utf8.elementsEqual(opportunity.title.utf8) { return providerText }
        return preparedText(for: opportunity, locale: session.language)?.title ?? session.title(for: opportunity)
    }

#if DEBUG
    /// Test-only seam: exercises the same retained-feed transition without a
    /// network or a signed publication. Never called by production UI.
    func retainPreparedFeedForTesting(_ response: OpportunityListResponse) async {
        await retainFullFeed(response, source: .previewDatabase)
    }
#endif

    init(
        api: APIClient,
        defaults: UserDefaults = .standard,
        notificationDelivery: any NewMatchNotificationDelivering = SystemNewMatchNotificationDelivery(),
        notificationScheduler: any OpportunityNotificationScheduling = SystemOpportunityNotificationScheduler(),
        now: @escaping () -> Date = { .now }
    ) {
        self.api = api
        self.defaults = defaults
        self.now = now
        self.notificationDelivery = notificationDelivery
        self.notificationScheduler = notificationScheduler
        if let data = defaults.data(forKey: Self.notificationPreferencesKey) {
            if data.count <= 4_000_000,
               let value = try? JSONDecoder().decode(OpportunityNotificationPreferences.self, from: data), value.isValid {
                notificationPreferences = value
            } else {
                notificationPreferencesReadable = false
                notificationStatusMessage = Self.localized("notificationSaveError")
            }
        }

        if let payload = defaults.data(forKey: Self.namedSearchesKey) {
            if payload.count <= 4_000_000,
               let archive = try? JSONDecoder().decode(NamedSearchArchive.self, from: payload),
               archive.version == 1, archive.searches.count <= 16,
               archive.searches.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 80 && $0.criteria.query.count <= 2_000 && $0.knownIDs.count <= 20_000 && $0.unreadIDs.isSubset(of: $0.knownIDs) }),
               Set(archive.searches.map(\.id)).count == archive.searches.count {
                savedSearches = archive.searches
            } else {
                // Preserve unknown/corrupt bytes instead of silently overwriting personal data.
                namedSearchStorageReadable = false
                savedSearchError = Self.localized("savedSearchWriteError")
            }
        }

        if let value = defaults.object(forKey: lastNotificationKey) as? TimeInterval {
            lastNotificationSentAt = Date(timeIntervalSince1970: value)
        }
    }

    func refresh(cache context: ModelContext? = nil, notifyOnNewMatches: Bool = false, force: Bool = false) async {
        // A forced refresh can bypass the short anti-thrashing interval, but it
        // must never create a second concurrent network request. A search or
        // filter change during that request still needs an immediate response,
        // so re-filter the retained full feed instead of appearing unresponsive.
        guard !isLoading else {
            await applyAvailableLocalResults(cache: context)
            persistCurrentHunt(in: context)
            return
        }
        guard force || shouldStartRefresh() else {
            // Preserve the anti-thrashing network limit without leaving the
            // visible results tied to the previous query or filters.
            await applyAvailableLocalResults(cache: context)
            persistCurrentHunt(in: context)
            return
        }
        // Claim the refresh before the first suspension point. Forced refreshes
        // bypass the time throttle, so the loading flag is the concurrency gate.
        isLoading = true
        defer {
            isLoading = false
            if Task.isCancelled && huntPhase == .hunting {
                huntPhase = opportunities.isEmpty ? .idle : .cached
            }
        }
        let now = self.now()
        lastHuntStartedAt = now
        lastRefreshStartedAt = now
        newMatchesCount = 0

        // Background refresh can be the first code path the system launches.
        // Establish a trusted cache/bundle baseline before comparing the live
        // feed so an existing catalog is not announced as entirely new. If no
        // trusted baseline exists, this run still records the live IDs but does
        // not send a misleading first-run notification.
        _ = await prepareNotificationBaselineIfNeeded(
            cache: context,
            notifyOnNewMatches: notifyOnNewMatches
        )
        await restoreLastHuntIfNeeded(in: context)
        huntPhase = .hunting
        do {
            let fullFeed = try await api.opportunityFeed()
            if let retained = inMemoryFeed,
               let revision = retained.publicationRevision,
               fullFeed.publicationRevision == revision,
               fullFeed.meta?.lastUpdated == retained.meta?.lastUpdated,
               fullFeed.data == retained.data {
                // Verify an unchanged publication without rewriting immutable
                // accepted bytes or reconciling saved events a second time.
                retainedFeedSource = .publicLiveFeed
                apply(await responseForCurrentHunt(from: retained), source: retainedFeedSource)
                persistCurrentHunt(in: context)
                lastSuccessfulHuntAt = self.now()
                huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
                errorMessage = nil
                await reconcileNamedSearches(with: fullFeed)
                if notifyOnNewMatches { await deliverSavedFilterAlerts(from: fullFeed) }
                return
            }
            if OpportunityFeedSelection.isOlder(fullFeed, than: inMemoryFeed, now: self.now()) {
                // A still-current production response can nevertheless predate
                // the app's bundled or cached feed. Preserve the newer retained
                // catalog and, critically, do not persist the older payload or
                // use it to mark saved events unavailable.
                await applyAvailableLocalResults(cache: context)
                persistCurrentHunt(in: context)
                huntPhase = dataSourceLabel == .publicLiveFeed ? .fresh : .cached
                errorMessage = nil
                if retainedFeedSource != .previewDatabase, let retained = inMemoryFeed {
                    await reconcileNamedSearches(with: retained)
                }
                return
            }
            // Encoding a large catalogue is CPU work; keep it off the UI actor.
            // Do not replace the retained feed until encoding has completed and
            // the refresh is still current; it may be cancelled while suspended.
            let previousGeneration = catalogueGeneration
            let cachePayload: Data?
            if context != nil {
                cachePayload = await Self.encodeCachePayload(fullFeed, limit: maximumCachePayloadBytes)
            } else {
                cachePayload = nil
            }
            guard !Task.isCancelled else { return }
#if DEBUG
            if let gate = cacheEncodingCommitGate { await gate() }
#endif
            guard !Task.isCancelled else { return }
            guard previousGeneration == catalogueGeneration else {
                await applyAvailableLocalResults(cache: context)
                persistCurrentHunt(in: context)
                huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
                return
            }
            let generation = await retainFullFeed(fullFeed, source: .publicLiveFeed)
            guard !Task.isCancelled else { return }
            let response = await responseForCurrentHunt(from: fullFeed)
            guard !Task.isCancelled else { return }
            guard generation == catalogueGeneration else {
                // A newer trusted retained feed can finish while filtering is
                // suspended. Do not persist or reconcile this superseded feed.
                await applyAvailableLocalResults(cache: context)
                persistCurrentHunt(in: context)
                huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
                return
            }
            let newCount = updateKnownIDs(in: fullFeed.data, matching: response.data)
            apply(response, source: retainedFeedSource)
            persist(cachePayload, in: context)
            if let context {
                _ = try? SavedOpportunityLibrary.reconcile(
                    with: fullFeed.data,
                    in: context,
                    markMissingAsUnavailable: fullFeed.permitsDestructiveSavedReconciliation,
                    restrictedOpportunityIDs: Set(
                        fullFeed.contentRights?.restrictedOpportunityIDs ?? []
                    )
                )
            }
            persistCurrentHunt(in: context)
            markSeen(response.data, in: context)
            await reconcileNamedSearches(with: fullFeed)
            newMatchesCount = newCount
            lastSuccessfulHuntAt = self.now()
            huntPhase = .fresh
            errorMessage = nil
            if notifyOnNewMatches { await deliverSavedFilterAlerts(from: fullFeed) }
        } catch {
            if let context {
                _ = await applyCachedResultsIfAvailableOffMain(in: context)
            }
            await applyBundledSnapshotIfNeeded()
            if !opportunities.isEmpty || lastUpdated != nil {
                huntPhase = .offline
                errorMessage = nil
            } else {
                huntPhase = .offline
                errorMessage = Self.localized("serverResponseInvalid")
            }
        }
    }

    func bootstrap(cache context: ModelContext?) async {
        _ = await prepareInitialSnapshot(cache: context)
        // Show a retained feed immediately, then ask the public source for a fresh
        // one on every cold launch. On a first install, the bundled snapshot keeps
        // the app useful while a slow public feed is still arriving. The 15-minute
        // throttle still protects active foreground transitions, but reopening the
        // app should not leave a user on a recent-yet-outdated cache when newer
        // events are available.
        await refresh(cache: context)
    }

    @discardableResult
    func prepareInitialSnapshot(cache context: ModelContext?) async -> Bool {
#if DEBUG
        let diagnosticStart = ProcessInfo.processInfo.systemUptime
        let arguments = ProcessInfo.processInfo.arguments
        let diagnosticNonce: String? = arguments.firstIndex(of: "-runtime-ready-nonce").flatMap { index in
            guard arguments.indices.contains(index + 1), UUID(uuidString: arguments[index + 1]) != nil else { return nil }
            return arguments[index + 1]
        }
        func observeStartup(_ phase: String) {
            guard let diagnosticNonce else { return }
            let elapsed = (ProcessInfo.processInfo.systemUptime - diagnosticStart) * 1_000
            FileHandle.standardOutput.write(Data(("GTA_STARTUP_PHASE \(diagnosticNonce) phase=\(phase) elapsed_ms=\(elapsed) rows=\(opportunities.count)\n").utf8))
        }
        observeStartup("begin")
#endif
        await restoreLastHuntIfNeeded(in: context)
#if DEBUG
        observeStartup("hunt-restored")
#endif
        if let context {
            await restoreCachedResultsIfAvailable(in: context)
        }
#if DEBUG
        observeStartup("cache-restored")
#endif
        await applyBundledSnapshotIfNeeded()
#if DEBUG
        observeStartup("bundle-considered")
#endif
        // The retained full feed may have been loaded by the launch experience
        // before a deep link or deterministic screenshot hunt was configured.
        // Always reapply the current query and filters before declaring the
        // interactive snapshot ready.
        await applyAvailableLocalResults(cache: context)
#if DEBUG
        observeStartup("current-hunt-filtered")
#endif
        if let inMemoryFeed {
            seedKnownIDsIfNeeded(with: inMemoryFeed.data)
        }
        if let context, let inMemoryFeed {
            _ = try? SavedOpportunityLibrary.reconcile(
                with: inMemoryFeed.data,
                in: context,
                markMissingAsUnavailable: false,
                restrictedOpportunityIDs: Set(
                    inMemoryFeed.contentRights?.restrictedOpportunityIDs ?? []
                )
            )
        }

#if DEBUG
        observeStartup("saved-reconciled")
#endif
        // A valid zero-result query still carries metadata, so it is launch-ready
        // even though its visible result list is empty.
        return !opportunities.isEmpty || lastUpdated != nil
    }

    /// Prepares the deterministic App Store capture surface from the exact
    /// release build. Static marketing images cannot carry the provider terms'
    /// required clickable source links, so they use clearly labelled,
    /// app-authored sample listings instead of third-party feed excerpts. This
    /// intentionally ignores disk cache and never starts a network request.
    @discardableResult
    func prepareScreenshotSnapshot() async -> Bool {
#if DEBUG
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-mac-translation-replay") {
            return await prepareMacTranslationReplay()
        }
#endif
        let fullFeed = ScreenshotOpportunityFixtures.fullFeed

        await retainFullFeed(fullFeed, source: .previewDatabase)
        apply(await responseForCurrentHunt(from: fullFeed), source: retainedFeedSource)
        huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
        errorMessage = nil
        return !opportunities.isEmpty || lastUpdated != nil
    }

#if DEBUG
    /// Isolated, source-linked record for a labelled replay of Mac output. Never published.
    func prepareMacTranslationReplay() async -> Bool {
        guard let feed = try? await Task.detached(priority: .userInitiated, operation: { try LocalOpportunitySnapshot.loadFull() }).value,
              let listing = feed.data.first(where: { $0.id == MacTranslationLayoutReplay.id }),
              FullDescriptionBinding.hash(listing.title) == MacTranslationLayoutReplay.titleHash,
              FullDescriptionBinding.hash(listing.description) == MacTranslationLayoutReplay.descriptionHash else { return false }
        let isolated = OpportunityListResponse(data: [listing], meta: .init(activeCount: 1, lastUpdated: feed.meta?.lastUpdated))
        await retainFullFeed(isolated, source: .previewDatabase)
        apply(isolated, source: retainedFeedSource)
        huntPhase = .cached
        errorMessage = nil
        return true
    }

    /// Labelled, isolated app-owned samples only; exercises the real baseline/delta engine.
    func prepareNamedSearchLayoutReview() async {
        let rows = ScreenshotOpportunityFixtures.fullFeed.data
        let sourceHealth = OpportunityListResponse.SourceHealth(
            library: .init(status: "healthy", attemptedPages: 1, successfulPages: 1,
                           pageSuccessRatio: 1, minimumPageSuccessRatio: 1,
                           acceptedListings: rows.count, minimumAcceptedListings: 1),
            discovery: .init(status: "healthy", sourcesChecked: 1, successfulSources: 1,
                             sourceSuccessRatio: 1, minimumSourceSuccessRatio: 1))
        let date = ISO8601DateFormatter().string(from: now())
        let baseline = OpportunityListResponse(data: rows.filter { $0.id != "sample-teen-code" }, meta: .init(activeCount: rows.count - 1, lastUpdated: date), sourceHealth: sourceHealth)
        let updated = OpportunityListResponse(data: rows, meta: .init(activeCount: rows.count, lastUpdated: date), sourceHealth: sourceHealth)
        var coding = OpportunityFilters(); coding.category = "Coding & Robotics"; coding.age = "16"
        var science = OpportunityFilters(); science.category = "Science & Engineering"; science.age = "10"
        let samples = [NamedSavedSearch(id: UUID(), name: "Sample: Creative coding", criteria: .init(query: "", mode: .all, filters: coding)),
                       NamedSavedSearch(id: UUID(), name: "Sample: Family science", criteria: .init(query: "", mode: .all, filters: science))]
        let snapshotNow = now()
        let result = await Task.detached(priority: .userInitiated) {
            let initial = NamedSearchMatching.reconcile(samples, with: baseline, language: .en, now: snapshotNow)
            return NamedSearchMatching.reconcile(initial, with: updated, language: .en, now: snapshotNow)
        }.value
        _ = await persistNamedSearches(result, expectedGeneration: namedSearchGeneration)
    }
#endif

    func refreshIfStale(cache context: ModelContext?) async {
        await restoreLastHuntIfNeeded(in: context)
        if let inMemoryFeed {
            apply(await responseForCurrentHunt(from: inMemoryFeed), source: retainedFeedSource)
        } else if let context {
            _ = await applyCachedResultsIfAvailableOffMain(in: context)
        }

        guard cacheNeedsRefresh(in: context) else { return }
        await refresh(cache: context)
    }

    func restoreLastHuntIfNeeded(in context: ModelContext?) async {
        guard !didRestoreLastHunt else { return }
        guard let context else { return }
        didRestoreLastHunt = true

        guard isUsingDefaultHunt else { return }

        do {
            let savedHuntKey = huntKey
            let descriptor = FetchDescriptor<SavedHuntRecord>(
                predicate: #Predicate { record in record.cacheKey == savedHuntKey },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return }

            query = record.query
            mode = SearchMode(rawValue: record.modeRawValue) ?? mode
            filters = OpportunityFilters(
                region: record.region,
                city: record.city,
                category: record.category,
                // Builds before 1.0 (12) displayed the persisted value "18"
                // as "18+". Migrate that saved selection to the corrected
                // adult-program bucket instead of restoring an invalid picker value.
                age: record.age == "18" ? "18+" : record.age,
                language: "all",
                latitude: record.latitude,
                longitude: record.longitude,
                distanceKm: record.distanceKm,
                sort: SearchSort(rawValue: record.sortRawValue) ?? filters.sort,
                includeNewFinds: record.includeNewFinds,
                volunteerHours: record.volunteerHours,
                coop: record.coop,
                mentorship: record.mentorship,
                scholarships: record.scholarships,
                blackFocused: record.blackFocused,
                girlsFocused: record.girlsFocused,
                indigenousFocused: record.indigenousFocused,
                leadership: record.leadership,
                requiredSupport: record.requiredSupportSelection,
                includeSupportOnRequest: record.includeSupportOnRequestRawValue ?? false
            )
            await restoreCachedResultsIfAvailable(in: context)
        } catch {
            errorMessage = Self.localizedMessage(for: error)
            didRestoreLastHunt = false
        }
    }

    func refreshForBackground() async {
        await refresh(cache: nil, notifyOnNewMatches: true)
    }

    func resetFilters() {
        filters = OpportunityFilters()
    }

    func clearPersonalHistory(in context: ModelContext) async throws {
        var retainedFeed = inMemoryFeed
        if retainedFeed == nil, let payload = cachedPayload(from: context) {
            retainedFeed = await Self.decodeCachedFullResponse(payload, now: self.now())
        }

        for record in try context.fetch(FetchDescriptor<SavedHuntRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SeenOpportunityRecord>()) {
            context.delete(record)
        }
        try context.save()

        // An explicit data reset also revokes all local reminder opt-ins.
        // Invalidate suspended permission/scheduling requests before cancelling.
        notificationPreferenceGeneration &+= 1
        notificationPreferences = OpportunityNotificationPreferences()
        notificationPreferencesReadable = true
        defaults.removeObject(forKey: Self.notificationPreferencesKey)
        await notificationScheduler.cancelDaily()
        defaults.removeObject(forKey: Self.namedSearchesKey)
        namedSearchStorageReadable = true
        savedSearches = []
        activeSavedSearchID = nil
        savedSearchError = nil
        namedSearchGeneration &+= 1
        defaults.removeObject(forKey: knownIDsKey)
        defaults.removeObject(forKey: lastNotificationKey)
        lastNotificationSentAt = nil
        didRestoreLastHunt = true
        lastHuntStartedAt = nil
        lastSuccessfulHuntAt = nil
        newMatchesCount = 0
        query = ""
        mode = .all
        filters = OpportunityFilters()
        await retainFullFeed(retainedFeed, source: .savedAppCache)
        if let retainedFeed {
            apply(await responseForCurrentHunt(from: retainedFeed), source: retainedFeedSource)
            huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
        } else {
            opportunities = []
            activeCount = 0
            lastUpdated = nil
            huntPhase = .idle
        }
    }

    func useCurrentLocation(_ coordinate: CLLocationCoordinate2D) {
        filters.latitude = coordinate.latitude
        filters.longitude = coordinate.longitude
        filters.city = ""
        filters.region = "All"
        filters.sort = .distance
    }

    func useCity(_ city: String) {
        // A city selection replaces a one-shot nearby/region constraint.
        clearLocation()
        filters.region = "All"
        filters.city = city
    }

    func clearLocation() {
        filters.latitude = nil
        filters.longitude = nil
        if filters.sort == .distance {
            filters.sort = .date
        }
    }

    func savedFilterAlertsEnabled(_ id: UUID) -> Bool {
        notificationPreferences.filters[id.uuidString] != nil
    }

    @discardableResult
    func setDailyReminder(enabled: Bool, hour: Int, minute: Int) async -> Bool {
        guard notificationPreferencesReadable, !isUpdatingNotificationPreferences,
              (0..<24).contains(hour), (0..<60).contains(minute) else { return false }
        isUpdatingNotificationPreferences = true
        let revision = notificationPreferenceGeneration
        defer { isUpdatingNotificationPreferences = false }
        if enabled {
            guard await notificationScheduler.requestPermission(),
                  await notificationScheduler.scheduleDaily(hour: hour, minute: minute,
                    title: "GTA FREE STEM", body: Self.localized("dailyReminderBody")) else {
                notificationStatusMessage = Self.localized("notificationPermissionHelp")
                return false
            }
        } else { await notificationScheduler.cancelDaily() }
        guard revision == notificationPreferenceGeneration else {
            if !notificationPreferences.dailyEnabled { await notificationScheduler.cancelDaily() }
            return false
        }
        let previous = notificationPreferences
        var next = previous
        next.dailyEnabled = enabled
        next.hour = hour
        next.minute = minute
        guard persistNotificationPreferences(next) else {
            if previous.dailyEnabled {
                _ = await notificationScheduler.scheduleDaily(hour: previous.hour, minute: previous.minute,
                    title: "GTA FREE STEM", body: Self.localized("dailyReminderBody"))
            } else { await notificationScheduler.cancelDaily() }
            return false
        }
        return true
    }

    @discardableResult
    func setSavedFilterAlerts(_ id: UUID, enabled: Bool) async -> Bool {
        guard notificationPreferencesReadable, !isUpdatingNotificationPreferences,
              savedSearches.contains(where: { $0.id == id }) else { return false }
        isUpdatingNotificationPreferences = true
        let revision = notificationPreferenceGeneration
        defer { isUpdatingNotificationPreferences = false }
        if enabled && !savedFilterAlertsEnabled(id) {
            guard await notificationScheduler.requestPermission() else {
                notificationStatusMessage = Self.localized("notificationPermissionHelp")
                return false
            }
        }
        guard revision == notificationPreferenceGeneration,
              let saved = savedSearches.first(where: { $0.id == id }) else { return false }
        var next = notificationPreferences
        if enabled {
            if next.filters[id.uuidString] == nil {
                next.filters[id.uuidString] = SavedFilterAlertState(acknowledgedIDs: saved.unreadIDs, hasBaseline: saved.hasBaseline)
            }
        } else { next.filters.removeValue(forKey: id.uuidString) }
        return persistNotificationPreferences(next)
    }

    private func persistNotificationPreferences(_ value: OpportunityNotificationPreferences) -> Bool {
        guard notificationPreferencesReadable, value.isValid,
              let data = try? JSONEncoder().encode(value), data.count <= 4_000_000 else {
            notificationStatusMessage = Self.localized("notificationSaveError")
            return false
        }
        defaults.set(data, forKey: Self.notificationPreferencesKey)
        notificationPreferences = value
        notificationStatusMessage = nil
        return true
    }

    private func deliverSavedFilterAlerts(from feed: OpportunityListResponse) async {
        guard !Task.isCancelled, !isDeliveringSavedFilterAlert,
              notificationPreferencesReadable, !notificationPreferences.filters.isEmpty else { return }
        isDeliveringSavedFilterAlert = true
        defer { isDeliveringSavedFilterAlert = false }
        let snapshotNow = now()
        let generationAtValidation = catalogueGeneration
        let valid = await Task.detached(priority: .utility) {
            NamedSearchMatching.isCompleteCatalog(feed, now: snapshotNow)
        }.value
        guard valid, !Task.isCancelled, generationAtValidation == catalogueGeneration else { return }
        var next = notificationPreferences
        var pending: [String: Set<String>] = [:]
        for search in savedSearches {
            let key = search.id.uuidString
            guard var state = next.filters[key], search.hasBaseline else { continue }
            if !state.hasBaseline {
                // The first healthy snapshot after enabling is a quiet baseline.
                state.hasBaseline = true
                state.acknowledgedIDs = search.unreadIDs
                next.filters[key] = state
            } else {
                let ids = search.unreadIDs.subtracting(state.acknowledgedIDs)
                if !ids.isEmpty { pending[key] = ids }
            }
        }
        if next != notificationPreferences { guard persistNotificationPreferences(next) else { return } }
        guard !pending.isEmpty,
              lastNotificationSentAt.map({ now().timeIntervalSince($0) >= minimumNotificationInterval }) ?? true else { return }
        let preferencesAtDelivery = notificationPreferences
        let resetRevision = notificationPreferenceGeneration
        let criteriaAtDelivery = Dictionary(uniqueKeysWithValues: savedSearches.map { ($0.id.uuidString, $0.criteria) })
        let count = pending.values.reduce(into: Set<String>()) { $0.formUnion($1) }.count
        // Generic lock-screen copy never exposes names, ages, community or access
        // needs from a person's saved filters. Shared matches are counted once.
        let delivered = await notificationDelivery.deliverNewMatchNotification(
            title: Self.localized("newOpportunitiesNotificationTitle"),
            body: Self.localized("savedFilterNotificationBody").replacingOccurrences(of: "{count}", with: "\(count)"))
        guard delivered, resetRevision == notificationPreferenceGeneration else { return }
        // Accepted delivery is a fact even if the task was cancelled immediately
        // afterwards. Persist it so an unrelated edit cannot repeat an alert.
        recordNotificationSent()
        next = notificationPreferences
        for (key, ids) in pending {
            guard next.filters[key] == preferencesAtDelivery.filters[key],
                  savedSearches.first(where: { $0.id.uuidString == key })?.criteria == criteriaAtDelivery[key]
            else { continue }
            next.filters[key]?.acknowledgedIDs.formUnion(ids)
        }
        _ = persistNotificationPreferences(next)
    }

    private func apply(_ response: OpportunityListResponse, source: DataSource) {
        opportunities = response.data
        activeCount = response.meta?.activeCount ?? response.data.count
        lastUpdated = response.meta?.lastUpdated
        dataSourceLabel = source
    }

    private func applyAvailableLocalResults(cache context: ModelContext?) async {
        if let inMemoryFeed {
            apply(await responseForCurrentHunt(from: inMemoryFeed), source: retainedFeedSource)
        } else if let context {
            _ = await applyCachedResultsIfAvailableOffMain(in: context)
        }
    }

    /// Capture sessions use app-owned samples and must never fetch a live feed.
    /// Normal browsing continues to refresh after filters are applied.
    func applyFilterSelection(cache context: ModelContext?, screenshotCapture: Bool = AppLaunchConfiguration.isScreenshotCapture) async {
        if screenshotCapture {
            await previewCurrentFilters()
        } else {
            await refresh(cache: context)
        }
    }

    /// Refilters the retained catalogue without fetching or persisting a feed.
    func previewCurrentFilters() async {
        localPreviewGeneration &+= 1
        let request = localPreviewGeneration
        guard !Task.isCancelled, let feed = inMemoryFeed else { return }
        let generation = catalogueGeneration
        let criteria = NamedSearchCriteria(query: query, mode: mode, filters: filters)
        let language = AppLanguage.preferred()
        let response = await responseForCurrentHunt(from: feed)
#if DEBUG
        if let gate = localPreviewCommitGate { await gate() }
#endif
        guard !Task.isCancelled, request == localPreviewGeneration,
              generation == catalogueGeneration, language == AppLanguage.preferred(),
              criteria == NamedSearchCriteria(query: query, mode: mode, filters: filters)
        else { return }
        apply(response, source: retainedFeedSource)
    }

    /// Explicit New filter/reset detaches the preset without changing a saved entry.
    func clearActiveSavedSearch() {
        activeSavedSearchID = nil
        localPreviewGeneration &+= 1
    }

    private func applyBundledSnapshotIfNeeded() async {
        guard let fullFeed = await Self.loadBundledFullFeed(now: self.now()) else {
            // The live refresh remains the authoritative path. If the packaged
            // snapshot is unavailable or corrupt, preserve the existing empty
            // state and let the interactive shell report the live refresh state.
            return
        }

        // A persisted cache can survive an App Store/TestFlight update. Prefer
        // whichever full feed declares the newer data change so an offline
        // updated app does not remain pinned to an older pre-update cache.
        guard OpportunityFeedSelection.shouldPrefer(fullFeed, over: inMemoryFeed, now: self.now()) else { return }

        await retainFullFeed(fullFeed, source: .previewDatabase)
        apply(await responseForCurrentHunt(from: fullFeed), source: retainedFeedSource)
        huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
        errorMessage = nil
    }

    nonisolated private static func loadBundledFullFeed(now: Date) async -> OpportunityListResponse? {
        await Task.detached(priority: .userInitiated) {
            try? LocalOpportunitySnapshot.loadFull(now: now)
        }.value
    }

    nonisolated static func encodeCachePayload(_ response: OpportunityListResponse, limit: Int) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let worker = Task.detached(priority: .utility) { () -> Data? in
            if let original = response.sourceFeedBytes {
                guard !Task.isCancelled, original.count <= limit else { return nil }
                return original
            }
            guard !Task.isCancelled, let payload = try? JSONEncoder().encode(response),
                  !Task.isCancelled, payload.count <= limit else { return nil }
            return payload
        }
        return await withTaskCancellationHandler(operation: {
            let payload = await worker.value
            return Task.isCancelled ? nil : payload
        }, onCancel: { worker.cancel() })
    }

    private func persist(_ payload: Data?, in context: ModelContext?) {
        guard let context, let payload else { return }
        do {
            let descriptor = FetchDescriptor<OpportunityCacheRecord>(
                predicate: #Predicate { record in record.cacheKey == "latest-opportunities" }
            )
            if let record = try context.fetch(descriptor).first {
                record.payload = payload
                record.updatedAt = now()
            } else {
                context.insert(OpportunityCacheRecord(cacheKey: cacheKey, payload: payload, updatedAt: now()))
            }
            try context.save()
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    private func cachedPayload(from context: ModelContext?) -> Data? {
        guard let context else { return nil }
        do {
            let descriptor = FetchDescriptor<OpportunityCacheRecord>(
                predicate: #Predicate { record in record.cacheKey == "latest-opportunities" },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return nil }
            guard record.payload.count <= maximumCachePayloadBytes else { return nil }
            return Data(record.payload)
        } catch {
            return nil
        }
    }

    nonisolated private static func decodeCachedFullResponse(_ payload: Data, now: Date) async -> OpportunityListResponse? {
        await Task.detached(priority: .userInitiated) { () -> OpportunityListResponse? in
            guard let response = try? JSONDecoder().decode(OpportunityListResponse.self, from: payload),
                  response.hasValidPublicationRevision(now: now) else { return nil }
            return APIClient.applyBundledTranslations(from: response, sourceFeedBytes: payload)
        }.value
    }

    private func persistCurrentHunt(in context: ModelContext?) {
        guard let context else { return }
        do {
            let descriptor = FetchDescriptor<SavedHuntRecord>(
                predicate: #Predicate { record in record.cacheKey == "last-hunt" }
            )
            if let record = try context.fetch(descriptor).first {
                record.query = query
                record.modeRawValue = mode.rawValue
                record.region = filters.region
                record.city = filters.city
                record.category = filters.category
                record.age = filters.age
                record.language = "all"
                record.latitude = filters.latitude
                record.longitude = filters.longitude
                record.distanceKm = filters.distanceKm
                record.sortRawValue = filters.sort.rawValue
                record.includeNewFinds = filters.includeNewFinds
                record.volunteerHours = filters.volunteerHours
                record.coop = filters.coop
                record.mentorship = filters.mentorship
                record.scholarships = filters.scholarships
                record.blackFocused = filters.blackFocused
                record.girlsFocused = filters.girlsFocused
                record.indigenousFocused = filters.indigenousFocused
                record.leadership = filters.leadership
                record.requiredSupportRawValue = SavedHuntRecord.encodeRequiredSupport(filters.requiredSupport)
                record.includeSupportOnRequestRawValue = filters.includeSupportOnRequest
                record.updatedAt = now()
            } else {
                context.insert(SavedHuntRecord(cacheKey: huntKey, query: query, mode: mode, filters: filters, updatedAt: now()))
            }
            try context.save()
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    private func restoreCachedResultsIfAvailable(in context: ModelContext) async {
        guard opportunities.isEmpty else { return }
        _ = await applyCachedResultsIfAvailableOffMain(in: context)
    }

    @discardableResult
    private func applyCachedResultsIfAvailableOffMain(in context: ModelContext) async -> Bool {
        guard let payload = cachedPayload(from: context) else { return false }
        guard let cached = await Self.decodeCachedFullResponse(payload, now: self.now()) else { return false }
        // Decode can suspend while a newer live refresh completes. Select again
        // after that suspension, and never roll retained data backwards on failure.
        guard OpportunityFeedSelection.shouldPrefer(cached, over: inMemoryFeed, now: self.now()) else {
            if let inMemoryFeed {
                apply(await responseForCurrentHunt(from: inMemoryFeed), source: retainedFeedSource)
            }
            return false
        }
        await retainFullFeed(cached, source: .savedAppCache)
        apply(await responseForCurrentHunt(from: cached), source: retainedFeedSource)
        huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
        return true
    }

    private func markSeen(_ opportunities: [Opportunity], in context: ModelContext?) {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<SeenOpportunityRecord>())
            let staleDate = now().addingTimeInterval(-seenRecordRetentionInterval)
            for record in records where record.lastSeenAt < staleDate {
                context.delete(record)
            }
            let existing = Dictionary(uniqueKeysWithValues: records
                .filter { $0.lastSeenAt >= staleDate }
                .map { ($0.opportunityID, $0) }
            )
            for opportunity in opportunities {
                if let record = existing[opportunity.id] {
                    record.lastSeenAt = now()
                } else {
                    let seenAt = now()
                    context.insert(SeenOpportunityRecord(opportunityID: opportunity.id, firstSeenAt: seenAt, lastSeenAt: seenAt))
                }
            }
            try context.save()
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    private func updateKnownIDs(in fullFeed: [Opportunity], matching filteredResults: [Opportunity]) -> Int {
        let result = KnownOpportunityHistory.merging(
            currentIDs: fullFeed.map(\.id),
            previousIDs: defaults.stringArray(forKey: knownIDsKey) ?? [],
            countingIDs: filteredResults.map(\.id)
        )
        defaults.set(result.retainedIDs, forKey: knownIDsKey)
        return result.newCount
    }

    private func seedKnownIDsIfNeeded(with opportunities: [Opportunity]) {
        guard !opportunities.isEmpty else { return }
        guard defaults.stringArray(forKey: knownIDsKey)?.isEmpty != false else { return }

        let result = KnownOpportunityHistory.merging(
            currentIDs: opportunities.map(\.id),
            previousIDs: []
        )
        defaults.set(result.retainedIDs, forKey: knownIDsKey)
    }

    private func prepareNotificationBaselineIfNeeded(
        cache context: ModelContext?,
        notifyOnNewMatches: Bool
    ) async -> Bool {
        guard notifyOnNewMatches else { return true }
        if defaults.stringArray(forKey: knownIDsKey)?.isEmpty == false {
            return true
        }

        if inMemoryFeed == nil, let context {
            await restoreCachedResultsIfAvailable(in: context)
        }
        await applyBundledSnapshotIfNeeded()
        if let inMemoryFeed {
            seedKnownIDsIfNeeded(with: inMemoryFeed.data)
        }

        return defaults.stringArray(forKey: knownIDsKey)?.isEmpty == false
    }

    private func shouldStartRefresh() -> Bool {
        if isLoading {
            return false
        }

        if let lastRefreshStartedAt, now().timeIntervalSince(lastRefreshStartedAt) < minimumRefreshInterval {
            return false
        }

        return true
    }

    private func responseForCurrentHunt(from response: OpportunityListResponse) async -> OpportunityListResponse {
        while true {
            let feed = inMemoryFeed ?? response
            let generation = catalogueGeneration
            let snapshotQuery = query
            let snapshotMode = mode
            let snapshotFilters = filters
            let snapshotLanguage = AppLanguage.preferred()
            let snapshotNow = now()
            let overlay = preparedListingOverlay.flatMap { value in
                value.locale == snapshotLanguage && retainedFeedSHA256 != nil &&
                value.generatedAt <= snapshotNow && snapshotNow < value.expiresAt ? value : nil
            }
            if preparedListingOverlay != nil && overlay == nil {
                preparedListingOverlay = nil
                preparedSearchIndex = nil
            }
            let feedSHA = retainedFeedSHA256
            let packSHA = overlay?.packSHA256
            let cachedIndex = preparedSearchIndex.flatMap {
                $0.generation == generation && $0.language == snapshotLanguage && $0.packSHA256 == packSHA ? $0.values : nil
            }
            let result = await Task.detached(priority: .userInitiated) {
                let index = snapshotQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? cachedIndex
                    : cachedIndex ?? LocalOpportunitySnapshot.prepareSearchIndex(feed.data, displayLanguage: snapshotLanguage, overlay: overlay, feedSHA256: feedSHA, now: snapshotNow)
                let filtered = LocalOpportunitySnapshot.filter(
                    feed.data, query: snapshotQuery, mode: snapshotMode,
                    filters: snapshotFilters, displayLanguage: snapshotLanguage, now: snapshotNow,
                    preparedSearchIndex: index, preparedOverlay: overlay, currentFeedSHA256: feedSHA
                )
                return (filtered: filtered, index: index)
            }.value
            // Reuse a completed index even if the query changed meanwhile;
            // its identity is the public feed and language, never the query.
            if generation == catalogueGeneration, snapshotLanguage == AppLanguage.preferred(),
               preparedListingOverlay?.packSHA256 == packSHA, let index = result.index {
                preparedSearchIndex = (generation, snapshotLanguage, packSHA, index)
            }
            // A keystroke, filter, language or accepted feed can change while
            // the worker runs. Never replace the newest hunt with an old result.
            guard generation == catalogueGeneration,
                  snapshotQuery == query, snapshotMode == mode,
                  snapshotFilters == filters, snapshotLanguage == AppLanguage.preferred(),
                  preparedListingOverlay?.packSHA256 == packSHA,
                  overlay.map({ now() < $0.expiresAt }) ?? true
            else { continue }
            return OpportunityListResponse(
                data: result.filtered,
                meta: OpportunityListResponse.Metadata(activeCount: result.filtered.count, lastUpdated: feed.meta?.lastUpdated),
                publicationRevision: feed.publicationRevision
            )
        }
    }

    private func cacheNeedsRefresh(in context: ModelContext?) -> Bool {
        guard let context else { return true }
        do {
            let descriptor = FetchDescriptor<OpportunityCacheRecord>(
                predicate: #Predicate { record in record.cacheKey == "latest-opportunities" },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return true }
            return now().timeIntervalSince(record.updatedAt) >= foregroundRefreshInterval
        } catch {
            return true
        }
    }


    // Named searches are explicit saves, separate from the legacy last-hunt record.
    @discardableResult
    func saveNamedSearch(name: String, updating id: UUID? = nil) async -> Bool {
        guard namedSearchStorageReadable else { savedSearchError = Self.localized("savedSearchWriteError"); return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, query.count <= 2_000 else { savedSearchError = Self.localized("savedSearchWriteError"); return false }
        let criteria = NamedSearchCriteria(query: query, mode: mode, filters: filters)
        let feed = retainedFeedSource == .publicLiveFeed && huntPhase != .offline ? inMemoryFeed : nil
        let generation = catalogueGeneration
        let revision = namedSearchGeneration
        let snapshotNow = now()
        let language = AppLanguage.preferred()
        let matches: Set<String>? = await Task.detached(priority: .userInitiated) {
            guard let feed, NamedSearchMatching.isCompleteCatalog(feed, now: snapshotNow) else { return nil }
            return NamedSearchMatching.ids(for: criteria, in: feed, language: language, now: snapshotNow)
        }.value
        guard !Task.isCancelled, generation == catalogueGeneration, revision == namedSearchGeneration else { return false }
        var next = savedSearches
        let saved = NamedSavedSearch(id: id ?? UUID(), name: trimmed, criteria: criteria,
                                     knownIDs: matches ?? [], unreadIDs: [], matchedCount: matches?.count,
                                     hasBaseline: matches != nil, checkedAt: matches == nil ? nil : snapshotNow,
                                     publicationDate: FeedPublicationRevision.date(from: feed?.publicationRevision)
                                        ?? FeedFreshness.date(from: feed?.meta?.lastUpdated))
        if let id {
            guard let index = next.firstIndex(where: { $0.id == id }) else { return false }
            next[index] = saved
        } else { next.append(saved) }
        guard await persistNamedSearches(next, expectedGeneration: revision) else { return false }
        activeSavedSearchID = saved.id
        if savedFilterAlertsEnabled(saved.id) {
            var preferences = notificationPreferences
            preferences.filters[saved.id.uuidString] = SavedFilterAlertState(acknowledgedIDs: saved.unreadIDs, hasBaseline: saved.hasBaseline)
            _ = persistNotificationPreferences(preferences)
        }
        return true
    }

    @discardableResult
    func openNamedSearch(_ id: UUID, acknowledge: Bool = true) async -> Bool {
        guard let saved = savedSearches.first(where: { $0.id == id }) else { return false }
        query = saved.criteria.query
        mode = saved.criteria.mode
        filters = saved.criteria.filters
        filters.language = "all"
        activeSavedSearchID = id
        let appliedCriteria = NamedSearchCriteria(query: query, mode: mode, filters: filters)
        await previewCurrentFilters()
        guard !Task.isCancelled, activeSavedSearchID == id,
              appliedCriteria == NamedSearchCriteria(query: query, mode: mode, filters: filters)
        else { return false }
        // A failed local write keeps unread evidence, but must not block browsing.
        if acknowledge { await markNamedSearchRead(id) }
        return !Task.isCancelled && activeSavedSearchID == id
            && appliedCriteria == NamedSearchCriteria(query: query, mode: mode, filters: filters)
    }

    func markNamedSearchRead(_ id: UUID) async {
        guard let index = savedSearches.firstIndex(where: { $0.id == id }) else { return }
        var next = savedSearches
        next[index].unreadIDs = []
        _ = await persistNamedSearches(next, expectedGeneration: namedSearchGeneration)
    }

    @discardableResult
    func deleteNamedSearch(_ id: UUID) async -> Bool {
        guard savedSearches.contains(where: { $0.id == id }) else { return false }
        guard await persistNamedSearches(savedSearches.filter { $0.id != id }, expectedGeneration: namedSearchGeneration) else { return false }
        if activeSavedSearchID == id { activeSavedSearchID = nil }
        var preferences = notificationPreferences
        preferences.filters.removeValue(forKey: id.uuidString)
        _ = persistNotificationPreferences(preferences)
        return true
    }

    func beginNewSearch(category: String = "All") {
        activeSavedSearchID = nil
        query = ""
        mode = .all
        filters = OpportunityFilters()
        filters.category = category
    }

    private func persistNamedSearches(_ searches: [NamedSavedSearch], expectedGeneration: Int, quietSupersession: Bool = false) async -> Bool {
        guard namedSearchStorageReadable else { savedSearchError = Self.localized("savedSearchWriteError"); return false }
        // Encoding stays off the UI actor. Never truncate history to make a write fit.
        let payload = await Task.detached(priority: .utility) { () -> Data? in
            guard searches.count <= 16, searches.allSatisfy({ $0.knownIDs.count <= 20_000 }) else { return nil }
            guard let payload = try? JSONEncoder().encode(NamedSearchArchive(searches: searches)), payload.count <= 4_000_000 else { return nil }
            return payload
        }.value
        guard !Task.isCancelled, expectedGeneration == namedSearchGeneration else {
            if !quietSupersession { savedSearchError = Self.localized("savedSearchWriteError") }
            return false
        }
        guard let payload else { savedSearchError = Self.localized("savedSearchWriteError"); return false }
        defaults.set(payload, forKey: Self.namedSearchesKey)
        savedSearches = searches
        namedSearchGeneration &+= 1
        savedSearchError = nil
        return true
    }

    private func reconcileNamedSearches(with feed: OpportunityListResponse) async {
        guard !savedSearches.isEmpty, namedSearchStorageReadable else { return }
        let snapshots = savedSearches
        let revision = namedSearchGeneration
        let generation = catalogueGeneration
        let snapshotNow = now()
        let language = AppLanguage.preferred()
        let worker = Task.detached(priority: .utility) {
            NamedSearchMatching.reconcile(snapshots, with: feed, language: language, now: snapshotNow)
        }
        let next = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
#if DEBUG
        if let gate = namedSearchReconciliationGate { await gate() }
#endif
        guard !Task.isCancelled, revision == namedSearchGeneration, generation == catalogueGeneration,
              next != savedSearches else { return }
        _ = await persistNamedSearches(next, expectedGeneration: revision, quietSupersession: true)
    }

    private var isUsingDefaultHunt: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            mode == .all &&
            filters == OpportunityFilters()
    }

    private func recordNotificationSent(at date: Date? = nil) {
        let sentAt = date ?? now()
        lastNotificationSentAt = sentAt
        defaults.set(sentAt.timeIntervalSince1970, forKey: lastNotificationKey)
    }

    private static func localized(_ key: String) -> String {
        let language = AppLanguage.preferred()
        return AppText.shared.string(key, language: language)
    }

    private static func localizedMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription,
           !message.isEmpty {
            return message
        }

        return localized("serverResponseInvalid")
    }
}

private enum ScreenshotOpportunityFixtures {
    static let fixtureIdentifier = "gta-free-stem-owned-samples-v1"
    private static let sourceURL = "https://gta-free-stem.pages.dev/support/"

    static let fullFeed = OpportunityListResponse(
        data: [
            sample(
                id: "sample-solar-robot",
                title: "Sample: Build a Solar Robot",
                summary: "Fictional preview listing created by GTA FREE STEM to demonstrate the app.",
                category: "Coding & Robotics",
                city: "Toronto",
                ageMin: 9,
                ageMax: 14,
                tags: ["sample", "robotics", "solar energy"]
            ),
            sample(
                id: "sample-space-studio",
                title: "Sample: Family Space Design Studio",
                summary: "Fictional preview listing created by GTA FREE STEM to demonstrate the app.",
                category: "Science & Engineering",
                city: "Scarborough",
                ageMin: 7,
                ageMax: 13,
                tags: ["sample", "space", "engineering"]
            ),
            sample(
                id: "sample-teen-code",
                title: "Sample: Teen Creative Coding Club",
                summary: "Fictional preview listing created by GTA FREE STEM to demonstrate the high-school view.",
                category: "Coding & Robotics",
                city: "North York",
                ageMin: 14,
                ageMax: 18,
                tags: ["sample", "high school", "teen", "creative coding"]
            ),
            sample(
                id: "sample-family-math",
                title: "Sample: Family Math Makers",
                summary: "Fictional preview listing created by GTA FREE STEM to demonstrate the app.",
                category: "Math & Data",
                city: "Markham",
                ageMin: 6,
                ageMax: 12,
                tags: ["sample", "math", "family"]
            )
        ],
        meta: OpportunityListResponse.Metadata(
            activeCount: 4,
            lastUpdated: "2026-08-20"
        )
    )

    private static func sample(
        id: String,
        title: String,
        summary: String,
        category: String,
        city: String,
        ageMin: Int,
        ageMax: Int,
        tags: [String]
    ) -> Opportunity {
        #if DEBUG
        let sampleAccessibility = ProcessInfo.processInfo.arguments.contains("-review-accessibility-notes")
            ? ["Sample: Step-free entrance; contact the provider for details."] : []
        let sampleSupport: AccessibilitySupport?
        if id == "sample-solar-robot", ProcessInfo.processInfo.arguments.contains("-review-support") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let object: [String: Any] = ["schemaVersion": 1, "evidence": [[
                "category": "sensory-friendly", "status": "provided", "scope": "activity",
                "sourceUrl": sourceURL, "evidenceText": "Sample: a quieter activity with a quiet break space.",
                "checkedAt": formatter.string(from: .now), "reviewStatus": "approved",
                "conditions": ["Sample: caregiver participation required; confirm arrangements before attending."]
            ]]]
            sampleSupport = (try? JSONSerialization.data(withJSONObject: object)).flatMap {
                try? JSONDecoder().decode(AccessibilitySupport.self, from: $0)
            }
        } else { sampleSupport = nil }
        #else
        let sampleAccessibility: [String] = []
        let sampleSupport: AccessibilitySupport? = nil
        #endif
        return Opportunity(
            id: id,
            title: title,
            organization: "GTA FREE STEM Sample Studio",
            description: summary,
            summary: summary,
            category: category,
            city: city,
            region: "Greater Toronto Area",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: nil,
            endDate: nil,
            deadline: nil,
            ageMin: ageMin,
            ageMax: ageMax,
            language: ["en"],
            cost: "Free",
            sourceUrl: sourceURL,
            registrationUrl: sourceURL,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: tags,
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: "App-authored screenshot sample",
            accessibility: sampleAccessibility,
            accessibilitySupport: sampleSupport
        )
    }
}

enum DataSource: String {
    case publicLiveFeed = "publicLiveFeed"
    case previewDatabase = "previewDatabase"
    case savedAppCache = "savedAppCache"
}

final class HuntLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var message: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestOneShotLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            message = Self.localized("lookingNearby")
            manager.requestLocation()
        case .denied, .restricted:
            message = Self.localized("locationOffChooseCity")
        @unknown default:
            message = Self.localized("locationUnavailable")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        message = coordinate == nil ? Self.localized("locationNotFound") : Self.localized("nearbyHuntingOn")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = Self.localized("locationUnavailable")
    }

    private static func localized(_ key: String) -> String {
        let language = AppLanguage.preferred()
        return AppText.shared.string(key, language: language)
    }
}
