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
    private var retainedFeedSource: DataSource = .publicLiveFeed
    private var preparedSearchIndex: (generation: Int, language: AppLanguage, values: [String: String])?

    /// Catalogue scans are CPU work. Keep them off the UI actor and publish
    /// their inventory only if this is still the retained feed on completion.
    @discardableResult
    private func retainFullFeed(_ response: OpportunityListResponse?, source: DataSource) async -> Int {
        catalogueGeneration &+= 1
        let generation = catalogueGeneration
        inMemoryFeed = response
        preparedSearchIndex = nil
        retainedFeedSource = source
        availableHomePathwayModes = []
        availableFilterCities = []
        availableFilterCategories = []
        guard let response else { return generation }
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
        return generation
    }

    init(
        api: APIClient,
        defaults: UserDefaults = .standard,
        notificationDelivery: any NewMatchNotificationDelivering = SystemNewMatchNotificationDelivery(),
        now: @escaping () -> Date = { .now }
    ) {
        self.api = api
        self.defaults = defaults
        self.now = now
        self.notificationDelivery = notificationDelivery

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
        defer { isLoading = false }
        let now = self.now()
        lastHuntStartedAt = now
        lastRefreshStartedAt = now
        newMatchesCount = 0

        // Background refresh can be the first code path the system launches.
        // Establish a trusted cache/bundle baseline before comparing the live
        // feed so an existing catalog is not announced as entirely new. If no
        // trusted baseline exists, this run still records the live IDs but does
        // not send a misleading first-run notification.
        let notificationBaselineIsReady = await prepareNotificationBaselineIfNeeded(
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
                return
            }
            let generation = await retainFullFeed(fullFeed, source: .publicLiveFeed)
            let response = await responseForCurrentHunt(from: fullFeed)
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
            persist(fullFeed, in: context)
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
            newMatchesCount = newCount
            lastSuccessfulHuntAt = self.now()
            huntPhase = .fresh
            errorMessage = nil
            if notificationBaselineIsReady,
               shouldNotifyOnBackgroundMatch(count: newCount, notifyOnNewMatches: notifyOnNewMatches) {
                let delivered = await sendNewMatchNotification(count: newCount)
                if delivered {
                    recordNotificationSent()
                }
            }
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
        await restoreLastHuntIfNeeded(in: context)
        if let context {
            await restoreCachedResultsIfAvailable(in: context)
        }
        await applyBundledSnapshotIfNeeded()
        // The retained full feed may have been loaded by the launch experience
        // before a deep link or deterministic screenshot hunt was configured.
        // Always reapply the current query and filters before declaring the
        // interactive snapshot ready.
        await applyAvailableLocalResults(cache: context)
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
        let fullFeed = ScreenshotOpportunityFixtures.fullFeed

        await retainFullFeed(fullFeed, source: .previewDatabase)
        apply(await responseForCurrentHunt(from: fullFeed), source: retainedFeedSource)
        huntPhase = retainedFeedSource == .publicLiveFeed ? .fresh : .cached
        errorMessage = nil
        return !opportunities.isEmpty || lastUpdated != nil
    }

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
                language: record.language,
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
                leadership: record.leadership
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

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            notificationStatusMessage = granted ? Self.localized("alertsOn") : Self.localized("alertsOff")
        } catch {
            notificationStatusMessage = Self.localizedMessage(for: error)
        }
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

    private func persist(_ response: OpportunityListResponse, in context: ModelContext?) {
        guard let context else { return }
        do {
            let payload = try JSONEncoder().encode(response)
            guard payload.count <= maximumCachePayloadBytes else { return }
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
            return response
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
                record.language = filters.language
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
            let cachedIndex = preparedSearchIndex.flatMap {
                $0.generation == generation && $0.language == snapshotLanguage ? $0.values : nil
            }
            let result = await Task.detached(priority: .userInitiated) {
                let index = snapshotQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? cachedIndex
                    : cachedIndex ?? LocalOpportunitySnapshot.prepareSearchIndex(feed.data, displayLanguage: snapshotLanguage)
                let filtered = LocalOpportunitySnapshot.filter(
                    feed.data, query: snapshotQuery, mode: snapshotMode,
                    filters: snapshotFilters, displayLanguage: snapshotLanguage, now: snapshotNow,
                    preparedSearchIndex: index
                )
                return (filtered: filtered, index: index)
            }.value
            // Reuse a completed index even if the query changed meanwhile;
            // its identity is the public feed and language, never the query.
            if generation == catalogueGeneration, snapshotLanguage == AppLanguage.preferred(), let index = result.index {
                preparedSearchIndex = (generation, snapshotLanguage, index)
            }
            // A keystroke, filter, language or accepted feed can change while
            // the worker runs. Never replace the newest hunt with an old result.
            guard generation == catalogueGeneration,
                  snapshotQuery == query, snapshotMode == mode,
                  snapshotFilters == filters, snapshotLanguage == AppLanguage.preferred()
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

    private var isUsingDefaultHunt: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            mode == .all &&
            filters == OpportunityFilters()
    }

    private func shouldNotifyOnBackgroundMatch(count: Int, notifyOnNewMatches: Bool) -> Bool {
        guard notifyOnNewMatches else { return false }
        guard count > 0 else { return false }
        if let sentAt = lastNotificationSentAt, now().timeIntervalSince(sentAt) < minimumNotificationInterval {
            return false
        }
        return true
    }

    private func sendNewMatchNotification(count: Int) async -> Bool {
        let title = Self.localized("newOpportunitiesNotificationTitle")
        let body = Self.localized("newOpportunitiesNotificationBody")
            .replacingOccurrences(of: "{count}", with: "\(count)")
        return await notificationDelivery.deliverNewMatchNotification(title: title, body: body)
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
        Opportunity(
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
            sourceConfidence: "App-authored screenshot sample"
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
