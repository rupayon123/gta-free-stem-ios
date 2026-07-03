import CoreLocation
import Foundation
import SwiftData
import UserNotifications

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
    @Published var shouldShowAccountRequiredAlert = false

    private let api: APIClient
    private let cacheKey = "latest-opportunities"
    private let huntKey = "last-hunt"
    private let knownIDsKey = "knownOpportunityIDs"
    private let lastNotificationKey = "lastNewOpportunityNotificationAt"
    private let minimumRefreshInterval: TimeInterval = 1.0
    private let minimumNotificationInterval: TimeInterval = 60 * 60
    private var lastNotificationSentAt: Date?
    private var lastRefreshStartedAt: Date?

    init(api: APIClient) {
        self.api = api

        if let value = UserDefaults.standard.object(forKey: lastNotificationKey) as? TimeInterval {
            lastNotificationSentAt = Date(timeIntervalSince1970: value)
        }
    }

    func refresh(cache context: ModelContext? = nil, prioritized: Bool = false, notifyOnNewMatches: Bool = false) async {
        guard shouldStartRefresh() else { return }
        let now = Date()
        lastHuntStartedAt = now
        lastRefreshStartedAt = now
        newMatchesCount = 0
        restoreLastHuntIfNeeded(in: context)
        huntPhase = .hunting
        isLoading = true
        defer { isLoading = false }
        do {
            if prioritized {
                do {
                    try await api.requestPrioritizedHunt(query: query, mode: mode, filters: filters)
                } catch {
                    // Best-effort kick for backend refresh; keep main feed fetch resilient.
                    errorMessage = Self.localizedMessage(for: error)
                }
            }
            let response = try await api.opportunities(query: query, mode: mode, filters: filters)
            let newCount = updateKnownIDs(with: response.data)
            apply(response, source: DataSource.publicLiveFeed)
            persist(response, in: context)
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
            if let cached = cachedResponse(from: context) {
                apply(cached, source: DataSource.savedAppCache)
                huntPhase = .cached
                errorMessage = nil
            } else {
                do {
                    let response = try LocalOpportunitySnapshot.load(query: query, mode: mode, filters: filters)
                    apply(response, source: DataSource.previewDatabase)
                    huntPhase = .offline
                    errorMessage = nil
                } catch {
                    huntPhase = .offline
                    errorMessage = Self.localized("serverResponseInvalid")
                }
            }
        }
    }

    func restoreLastHuntIfNeeded(in context: ModelContext?) {
        guard !didRestoreLastHunt else { return }
        guard let context else { return }
        didRestoreLastHunt = true

        do {
            let descriptor = FetchDescriptor<SavedHuntRecord>(
                predicate: #Predicate { record in record.cacheKey == huntKey },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return }

            query = record.query
            mode = SearchMode(rawValue: record.modeRawValue) ?? mode
            filters = OpportunityFilters(
                region: record.region,
                city: record.city,
                category: record.category,
                age: record.age,
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
            restoreCachedResultsIfAvailable(in: context)
        } catch {
            errorMessage = Self.localizedMessage(for: error)
            didRestoreLastHunt = false
        }
    }

    func refreshForBackground() async {
        await refresh(cache: nil, prioritized: false, notifyOnNewMatches: true)
    }

    func resetFilters() {
        filters = OpportunityFilters()
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

    func save(_ opportunity: Opportunity, token: String?) async {
        do {
            try await api.save(opportunityID: opportunity.id, token: token)
            errorMessage = Self.localized("saved")
            shouldShowAccountRequiredAlert = false
        } catch {
            errorMessage = Self.localizedMessage(for: error)
            shouldShowAccountRequiredAlert = (error as? APIError) == .accountRequired
        }
    }

    private func apply(_ response: OpportunityListResponse, source: DataSource) {
        opportunities = response.data
        activeCount = response.meta?.activeCount ?? response.data.count
        lastUpdated = response.meta?.lastUpdated
        dataSourceLabel = source
    }

    private func persist(_ response: OpportunityListResponse, in context: ModelContext?) {
        guard let context else { return }
        do {
            let payload = try JSONEncoder().encode(response)
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

    private func cachedResponse(from context: ModelContext?) -> OpportunityListResponse? {
        guard let context else { return nil }
        do {
            let descriptor = FetchDescriptor<OpportunityCacheRecord>(
                predicate: #Predicate { record in record.cacheKey == "latest-opportunities" },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            guard let record = try context.fetch(descriptor).first else { return nil }
            let response = try JSONDecoder().decode(OpportunityListResponse.self, from: record.payload)
            let filtered = LocalOpportunitySnapshot.filter(response.data, query: query, mode: mode, filters: filters)
            return OpportunityListResponse(
                data: filtered,
                meta: OpportunityListResponse.Metadata(activeCount: response.meta?.activeCount ?? filtered.count, lastUpdated: response.meta?.lastUpdated)
            )
        } catch {
            return nil
        }
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

    private func restoreCachedResultsIfAvailable(in context: ModelContext) {
        guard opportunities.isEmpty, let cached = cachedResponse(from: context) else { return }
        apply(cached, source: DataSource.savedAppCache)
        huntPhase = .cached
    }

    private func markSeen(_ opportunities: [Opportunity], in context: ModelContext?) {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<SeenOpportunityRecord>())
            let existing = Dictionary(uniqueKeysWithValues: records.map { ($0.opportunityID, $0) })
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
        let ids = Set(opportunities.map(\.id))
        let known = Set(UserDefaults.standard.stringArray(forKey: knownIDsKey) ?? [])
        let newIDs = ids.subtracting(known)
        let recentKnownIDs = Array(Array(known.union(ids)).suffix(2_500))
        UserDefaults.standard.set(recentKnownIDs, forKey: knownIDsKey)
        return newIDs.count
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
    case railsAPI = "railsAPI"
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
