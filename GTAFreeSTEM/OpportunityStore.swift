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
    /// Returns true when a candidate retained feed is more useful or newer than
    /// the currently selected one. Equal dates keep the existing source so a
    /// validated live cache is not replaced unnecessarily by bundled data.
    static func shouldPrefer(_ candidate: OpportunityListResponse, over retained: OpportunityListResponse?) -> Bool {
        let candidateIsUsable = !candidate.data.isEmpty || candidate.meta?.lastUpdated != nil
        guard candidateIsUsable else { return false }
        guard let retained else { return true }

        let retainedIsUsable = !retained.data.isEmpty || retained.meta?.lastUpdated != nil
        guard retainedIsUsable else { return true }

        let candidateDate = FeedFreshness.date(from: candidate.meta?.lastUpdated)
        let retainedDate = FeedFreshness.date(from: retained.meta?.lastUpdated)
        switch (candidateDate, retainedDate) {
        case let (.some(candidateDate), .some(retainedDate)):
            return candidateDate > retainedDate
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
        limit: Int = maximumCount
    ) -> (retainedIDs: [String], newCount: Int) {
        let normalizedLimit = max(0, limit)
        let current = unique(currentIDs)
        let previous = unique(previousIDs)
        let previousSet = Set(previous)
        let newCount = current.reduce(into: 0) { count, id in
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

    private let api: APIClient
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

    init(api: APIClient) {
        self.api = api

        if let value = UserDefaults.standard.object(forKey: lastNotificationKey) as? TimeInterval {
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
        let now = Date()
        lastHuntStartedAt = now
        lastRefreshStartedAt = now
        newMatchesCount = 0
        await restoreLastHuntIfNeeded(in: context)
        huntPhase = .hunting
        isLoading = true
        defer { isLoading = false }
        do {
            let fullFeed = try await api.opportunityFeed()
            inMemoryFeed = fullFeed
            let response = responseForCurrentHunt(from: fullFeed)
            let newCount = updateKnownIDs(with: response.data)
            apply(response, source: DataSource.publicLiveFeed)
            persist(fullFeed, in: context)
            if let context {
                _ = try? SavedOpportunityLibrary.reconcile(
                    with: fullFeed.data,
                    in: context,
                    markMissingAsUnavailable: fullFeed.permitsDestructiveSavedReconciliation
                )
            }
            persistCurrentHunt(in: context)
            markSeen(response.data, in: context)
            newMatchesCount = newCount
            lastSuccessfulHuntAt = .now
            huntPhase = .fresh
            errorMessage = nil
            if shouldNotifyOnBackgroundMatch(count: newCount, notifyOnNewMatches: notifyOnNewMatches) {
                await sendNewMatchNotification(count: newCount)
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
        if let context, let inMemoryFeed {
            _ = try? SavedOpportunityLibrary.reconcile(
                with: inMemoryFeed.data,
                in: context,
                markMissingAsUnavailable: false
            )
        }

        // A valid zero-result query still carries metadata, so it is launch-ready
        // even though its visible result list is empty.
        return !opportunities.isEmpty || lastUpdated != nil
    }

    /// Prepares the deterministic App Store capture surface from the exact
    /// bundled release feed. This intentionally ignores disk cache and never
    /// starts a network request, so capture readiness cannot race a stale or
    /// changing public response.
    @discardableResult
    func prepareScreenshotSnapshot() async -> Bool {
        guard let fullFeed = await Self.loadBundledFullFeed() else { return false }

        inMemoryFeed = fullFeed
        apply(responseForCurrentHunt(from: fullFeed), source: .previewDatabase)
        huntPhase = .cached
        errorMessage = nil
        return !opportunities.isEmpty || lastUpdated != nil
    }

    func refreshIfStale(cache context: ModelContext?) async {
        await restoreLastHuntIfNeeded(in: context)
        if let inMemoryFeed {
            apply(responseForCurrentHunt(from: inMemoryFeed), source: dataSourceLabel)
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
            retainedFeed = await Self.decodeCachedFullResponse(payload)
        }

        for record in try context.fetch(FetchDescriptor<SavedHuntRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SeenOpportunityRecord>()) {
            context.delete(record)
        }
        try context.save()

        UserDefaults.standard.removeObject(forKey: knownIDsKey)
        UserDefaults.standard.removeObject(forKey: lastNotificationKey)
        lastNotificationSentAt = nil
        didRestoreLastHunt = true
        lastHuntStartedAt = nil
        lastSuccessfulHuntAt = nil
        newMatchesCount = 0
        query = ""
        mode = .all
        filters = OpportunityFilters()
        inMemoryFeed = retainedFeed
        if let retainedFeed {
            apply(responseForCurrentHunt(from: retainedFeed), source: .savedAppCache)
            huntPhase = .cached
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
            apply(responseForCurrentHunt(from: inMemoryFeed), source: dataSourceLabel)
        } else if let context {
            _ = await applyCachedResultsIfAvailableOffMain(in: context)
        }
    }

    private func applyBundledSnapshotIfNeeded() async {
        guard let fullFeed = await Self.loadBundledFullFeed() else {
            // The live refresh remains the authoritative path. If the packaged
            // snapshot is unavailable or corrupt, preserve the existing empty
            // state and let the interactive shell report the live refresh state.
            return
        }

        // A persisted cache can survive an App Store/TestFlight update. Prefer
        // whichever full feed declares the newer data change so an offline
        // updated app does not remain pinned to an older pre-update cache.
        guard OpportunityFeedSelection.shouldPrefer(fullFeed, over: inMemoryFeed) else { return }

        inMemoryFeed = fullFeed
        apply(responseForCurrentHunt(from: fullFeed), source: .previewDatabase)
        huntPhase = .cached
        errorMessage = nil
    }

    nonisolated private static func loadBundledFullFeed() async -> OpportunityListResponse? {
        await Task.detached(priority: .userInitiated) {
            try? LocalOpportunitySnapshot.loadFull()
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
                record.updatedAt = .now
            } else {
                context.insert(OpportunityCacheRecord(cacheKey: cacheKey, payload: payload))
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

    nonisolated private static func decodeCachedFullResponse(_ payload: Data) async -> OpportunityListResponse? {
        await Task.detached(priority: .userInitiated) {
            try? JSONDecoder().decode(OpportunityListResponse.self, from: payload)
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
                record.updatedAt = .now
            } else {
                context.insert(SavedHuntRecord(cacheKey: huntKey, query: query, mode: mode, filters: filters))
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
        guard let cached = await Self.decodeCachedFullResponse(payload) else { return false }
        inMemoryFeed = cached
        apply(responseForCurrentHunt(from: cached), source: DataSource.savedAppCache)
        huntPhase = .cached
        return true
    }

    private func markSeen(_ opportunities: [Opportunity], in context: ModelContext?) {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<SeenOpportunityRecord>())
            let staleDate = Date().addingTimeInterval(-seenRecordRetentionInterval)
            for record in records where record.lastSeenAt < staleDate {
                context.delete(record)
            }
            let existing = Dictionary(uniqueKeysWithValues: records
                .filter { $0.lastSeenAt >= staleDate }
                .map { ($0.opportunityID, $0) }
            )
            for opportunity in opportunities {
                if let record = existing[opportunity.id] {
                    record.lastSeenAt = .now
                } else {
                    context.insert(SeenOpportunityRecord(opportunityID: opportunity.id))
                }
            }
            try context.save()
        } catch {
            errorMessage = Self.localizedMessage(for: error)
        }
    }

    private func updateKnownIDs(with opportunities: [Opportunity]) -> Int {
        let result = KnownOpportunityHistory.merging(
            currentIDs: opportunities.map(\.id),
            previousIDs: UserDefaults.standard.stringArray(forKey: knownIDsKey) ?? []
        )
        UserDefaults.standard.set(result.retainedIDs, forKey: knownIDsKey)
        return result.newCount
    }

    private func shouldStartRefresh() -> Bool {
        if isLoading {
            return false
        }

        if let lastRefreshStartedAt, Date().timeIntervalSince(lastRefreshStartedAt) < minimumRefreshInterval {
            return false
        }

        return true
    }

    private func responseForCurrentHunt(from response: OpportunityListResponse) -> OpportunityListResponse {
        let filtered = LocalOpportunitySnapshot.filter(response.data, query: query, mode: mode, filters: filters)
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(activeCount: filtered.count, lastUpdated: response.meta?.lastUpdated)
        )
    }

    private func cacheNeedsRefresh(in context: ModelContext?) -> Bool {
        guard let context else { return true }
        do {
            let descriptor = FetchDescriptor<OpportunityCacheRecord>(
                predicate: #Predicate { record in record.cacheKey == "latest-opportunities" },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return true }
            return Date().timeIntervalSince(record.updatedAt) >= foregroundRefreshInterval
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
        if let sentAt = lastNotificationSentAt, Date().timeIntervalSince(sentAt) < minimumNotificationInterval {
            return false
        }
        lastNotificationSentAt = .now
        UserDefaults.standard.set(lastNotificationSentAt?.timeIntervalSince1970, forKey: lastNotificationKey)
        return true
    }

    private func sendNewMatchNotification(count: Int) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.localized("newOpportunitiesNotificationTitle")
        content.body = Self.localized("newOpportunitiesNotificationBody")
            .replacingOccurrences(of: "{count}", with: "\(count)")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "new-opportunities-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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
