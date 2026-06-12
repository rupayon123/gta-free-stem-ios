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
        case .cached: "externaldrive.fill.badge.checkmark"
        case .offline: "archivebox.fill"
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
    @Published var dataSourceLabel = "Rails API"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var huntPhase: HuntPhase = .idle
    @Published var lastHuntStartedAt: Date?
    @Published var lastSuccessfulHuntAt: Date?
    @Published var newMatchesCount = 0
    @Published var notificationStatusMessage: String?

    private let api: APIClient
    private let cacheKey = "latest-opportunities"
    private let huntKey = "last-hunt"
    private let knownIDsKey = "knownOpportunityIDs"

    init(api: APIClient) {
        self.api = api
    }

    func refresh(cache context: ModelContext? = nil, prioritized: Bool = false, notifyOnNewMatches: Bool = false) async {
        lastHuntStartedAt = .now
        huntPhase = .hunting
        isLoading = true
        defer { isLoading = false }
        do {
            if prioritized {
                try? await api.requestPrioritizedHunt(query: query, mode: mode, filters: filters)
            }
            let response = try await api.opportunities(query: query, mode: mode, filters: filters)
            let newCount = updateKnownIDs(with: response.data)
            apply(response, source: "Rails API")
            persist(response, in: context)
            persistCurrentHunt(in: context)
            markSeen(response.data, in: context)
            newMatchesCount = newCount
            lastSuccessfulHuntAt = .now
            huntPhase = .fresh
            errorMessage = nil
            if notifyOnNewMatches, newCount > 0 {
                await sendNewMatchNotification(count: newCount)
            }
        } catch {
            if let cached = cachedResponse(from: context) {
                apply(cached, source: "Saved app cache")
                huntPhase = .cached
                errorMessage = nil
            } else {
                do {
                let response = try LocalOpportunitySnapshot.load(query: query, mode: mode, filters: filters)
                apply(response, source: "Preview database")
                huntPhase = .offline
                errorMessage = nil
                } catch {
                    huntPhase = .offline
                    errorMessage = error.localizedDescription
                }
            }
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
            notificationStatusMessage = error.localizedDescription
        }
    }

    func save(_ opportunity: Opportunity, token: String?) async {
        do {
            try await api.save(opportunityID: opportunity.id, token: token)
            errorMessage = Self.localized("saved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ response: OpportunityListResponse, source: String) {
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
            errorMessage = error.localizedDescription
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
                record.updatedAt = .now
            } else {
                context.insert(SavedHuntRecord(cacheKey: huntKey, query: query, mode: mode, filters: filters))
            }
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
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
            errorMessage = error.localizedDescription
        }
    }

    private func updateKnownIDs(with opportunities: [Opportunity]) -> Int {
        let ids = Set(opportunities.map(\.id))
        let known = Set(UserDefaults.standard.stringArray(forKey: knownIDsKey) ?? [])
        let newIDs = ids.subtracting(known)
        UserDefaults.standard.set(Array(known.union(ids)).suffix(2_500), forKey: knownIDsKey)
        return newIDs.count
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
        let stored = UserDefaults.standard.string(forKey: "preferredLanguageCode")
        let language = AppLanguage.normalized(stored ?? AppLanguage.en.rawValue)
        return AppText.shared.string(key, language: language)
    }
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
        message = error.localizedDescription
    }

    private static func localized(_ key: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "preferredLanguageCode")
        let language = AppLanguage.normalized(stored ?? AppLanguage.en.rawValue)
        return AppText.shared.string(key, language: language)
    }
}
