import Foundation
import SwiftUI
@preconcurrency import WatchConnectivity

private enum WatchLanguage: String, CaseIterable, Sendable {
    case en
    case fr
    case zh
    case yue
    case pa
    case ur
    case ta
    case tl
    case es
    case ar
    case fa
    case hi
    case pt
    case gu
    case bn
    case ja
    case ko
    case hu

    var localeIdentifier: String {
        switch self {
        case .zh: "zh-Hans"
        case .yue: "yue-Hant"
        case .tl: "fil"
        default: rawValue
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .ar, .fa, .ur: .rightToLeft
        default: .leftToRight
        }
    }

    static func preferred(from preferredLanguages: [String] = Locale.preferredLanguages) -> WatchLanguage {
        preferredLanguages.lazy.compactMap(resolve(_:)).first ?? .en
    }

    static func resolve(_ value: String) -> WatchLanguage? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if let exact = WatchLanguage(rawValue: normalized) {
            return exact
        }

        // Cantonese is a supported Traditional-script catalog. Resolve its
        // yue and legacy zh-yue tags before rejecting unsupported Traditional
        // Mandarin tags such as zh-Hant-TW.
        if normalized == "cantonese" || normalized == "cantonese/yue" ||
            normalized == "yue" || normalized.hasPrefix("yue-") ||
            normalized == "zh-yue" || normalized.hasPrefix("zh-yue-") {
            return .yue
        }

        // This companion has Simplified Mandarin and Cantonese catalogs, but
        // no Traditional Mandarin catalog. Match the iPhone app's behavior by
        // continuing to the next preferred locale instead of silently showing
        // Simplified Mandarin to a Traditional Mandarin reader.
        if normalized.hasPrefix("zh-") {
            let subtags = normalized.split(separator: "-").map(String.init)
            if subtags.contains("hant") || subtags.contains("tw") || subtags.contains("hk") || subtags.contains("mo") {
                return nil
            }
        }

        if normalized == "mandarin" || normalized == "mandarin (simplified)" ||
            normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
            return .zh
        }
        if normalized == "fil" || normalized == "filipino" || normalized == "tagalog" || normalized == "tagalog/filipino" || normalized.hasPrefix("fil-") {
            return .tl
        }

        guard let primary = normalized.split(separator: "-").first else { return nil }
        return WatchLanguage(rawValue: String(primary))
    }
}

private enum WatchText: String, CaseIterable, Sendable {
    case syncUnavailable = "watch.syncUnavailable"
    case openPhoneToRefresh = "watch.openPhoneToRefresh"
    case latestSavedOnWatch = "watch.latestSavedOnWatch"
    case updatePhoneApp = "watch.updatePhoneApp"
    case locationInDetails = "watch.locationInDetails"
    case eventDetails = "watch.eventDetails"
    case timingInDetails = "watch.timingInDetails"
    case date = "watch.date"
    case yourEventsTitle = "watch.yourEventsTitle"
    case yourEventsMessage = "watch.yourEventsMessage"
    case trySync = "watch.trySync"
    case noSavedEvents = "watch.noSavedEvents"
    case noSavedEventsMessage = "watch.noSavedEventsMessage"
    case checkAgain = "watch.checkAgain"
    case myStemPlan = "watch.myStemPlan"
    case savedEvents = "watch.savedEvents"
    case syncSavedFromPhone = "watch.syncSavedFromPhone"
    case connectPhone = "watch.connectPhone"
    case eventComingOne = "watch.eventComingOne"
    case eventsComingMany = "watch.eventsComingMany"
    case nothingUpcoming = "watch.nothingUpcoming"
    case archiveStillAvailable = "watch.archiveStillAvailable"
    case upcoming = "watch.upcoming"
    case synced = "watch.synced"
    case showingSavedEvents = "watch.showingSavedEvents"
    case nextEventLabel = "watch.nextEventLabel"
    case openEventDetails = "watch.openEventDetails"
    case eventArchive = "watch.eventArchive"
    case pastSavedEventOne = "watch.pastSavedEventOne"
    case pastSavedEventsMany = "watch.pastSavedEventsMany"
    case openArchivedEvents = "watch.openArchivedEvents"
    case noArchivedEvents = "watch.noArchivedEvents"
    case archivedEventsDescription = "watch.archivedEventsDescription"
    case archive = "watch.archive"
    case eventDetailsTitle = "watch.eventDetailsTitle"
    case pastEvent = "watch.pastEvent"
    case savedEvent = "watch.savedEvent"
    case when = "watch.when"
    case applyBy = "watch.applyBy"
    case `where` = "watch.where"
    case checkFinalLocation = "watch.checkFinalLocation"
    case roomDetails = "watch.roomDetails"
    case openRegistrationForDetails = "watch.openRegistrationForDetails"
    case directionsInMaps = "watch.directionsInMaps"
    case opensMapsHint = "watch.opensMapsHint"
    case registrationDetails = "watch.registrationDetails"

    var english: String {
        switch self {
        case .syncUnavailable: "Watch sync is unavailable on this device."
        case .openPhoneToRefresh: "Open GTA FREE STEM on your iPhone to refresh saved events."
        case .latestSavedOnWatch: "Still showing the latest events saved on this watch."
        case .updatePhoneApp: "Update the iPhone app to sync saved events."
        case .locationInDetails: "Location in event details"
        case .eventDetails: "Event details"
        case .timingInDetails: "See event details for timing"
        case .date: "DATE"
        case .yourEventsTitle: "Your events, at a glance"
        case .yourEventsMessage: "Open GTA FREE STEM on your iPhone, save an event, then sync it here."
        case .trySync: "Try sync"
        case .noSavedEvents: "No saved events"
        case .noSavedEventsMessage: "Save an event in the iPhone app and it will appear here, ready for your wrist."
        case .checkAgain: "Check again"
        case .myStemPlan: "MY STEM PLAN"
        case .savedEvents: "Saved events"
        case .syncSavedFromPhone: "Sync saved events from iPhone"
        case .connectPhone: "Connect your iPhone"
        case .eventComingOne: "1 event coming up"
        case .eventsComingMany: "{count} events coming up"
        case .nothingUpcoming: "Nothing upcoming"
        case .archiveStillAvailable: "Your past saved events are still available in the archive."
        case .upcoming: "UPCOMING"
        case .synced: "Synced {value}"
        case .showingSavedEvents: "Showing {shown} of {total} saved events"
        case .nextEventLabel: "Next event. {title}. {time}. {place}"
        case .openEventDetails: "Open event details"
        case .eventArchive: "Event archive"
        case .pastSavedEventOne: "1 past saved event"
        case .pastSavedEventsMany: "{count} past saved events"
        case .openArchivedEvents: "Open archived events"
        case .noArchivedEvents: "No archived events"
        case .archivedEventsDescription: "Saved events appear here after their date and time pass."
        case .archive: "Archive"
        case .eventDetailsTitle: "Event details"
        case .pastEvent: "PAST EVENT"
        case .savedEvent: "SAVED EVENT"
        case .when: "WHEN"
        case .applyBy: "Apply by {date}"
        case .where: "WHERE"
        case .checkFinalLocation: "Check the event details for the final room or meeting point."
        case .roomDetails: "ROOM & DETAILS"
        case .openRegistrationForDetails: "Open the registration page for room and arrival details."
        case .directionsInMaps: "Directions in Maps"
        case .opensMapsHint: "Opens Apple Maps with directions to this event"
        case .registrationDetails: "Registration details"
        }
    }
}

private struct WatchLocalization: Sendable {
    let language: WatchLanguage

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func text(_ key: WatchText, replacing replacements: [String: String] = [:]) -> String {
        let base = WatchStringCatalog.shared.string(key, language: language) ?? key.english
        return replacements.reduce(base) { result, replacement in
            result.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }

    func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func relativeDate(_ value: Date, relativeTo reference: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: value, relativeTo: reference)
    }

    func shortDateTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        formatter.setLocalizedDateFormatFromTemplate("MMMdhm")
        return formatter.string(from: value)
    }
}

private final class WatchStringCatalog: @unchecked Sendable {
    static let shared = WatchStringCatalog()

    private let strings: [String: [String: String]]

    private init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "WatchStrings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            strings = [:]
            return
        }
        strings = decoded
    }

    func string(_ key: WatchText, language: WatchLanguage) -> String? {
        guard let value = strings[language.rawValue]?[key.rawValue]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct WatchLocalizationEnvironmentKey: EnvironmentKey {
    static let defaultValue = WatchLocalization(language: .en)
}

private extension EnvironmentValues {
    var watchLocalization: WatchLocalization {
        get { self[WatchLocalizationEnvironmentKey.self] }
        set { self[WatchLocalizationEnvironmentKey.self] = newValue }
    }
}

@main
struct GTAFreeSTEMWatchApp: App {
    @StateObject private var store = WatchOpportunityStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .environment(\.watchLocalization, store.localization)
                .environment(\.locale, store.localization.locale)
                .environment(\.layoutDirection, store.language.layoutDirection)
        }
    }
}

@MainActor
private final class WatchOpportunityStore: NSObject, ObservableObject, WCSessionDelegate {
    private enum SyncKey {
        static let payload = "savedEventsPayload"
        static let request = "requestSavedEvents"
        static let preferredLanguage = "preferredLanguageCode"
    }

    private static let cacheKey = "watch-saved-events-v1"
    private static let languageCacheKey = "watch-preferred-language-v1"

    @Published private(set) var events = [WatchSavedEvent]()
    @Published private(set) var totalSavedCount = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var hasSynced = false
    @Published private(set) var isSyncing = false
    @Published private(set) var syncNote: WatchText?
    @Published private(set) var language: WatchLanguage

    private let defaults: UserDefaults
    private var didLoad = false
    private var latestRequestAt: Date?

    var upcomingEvents: [WatchSavedEvent] {
        events
            .filter { !$0.isArchived() }
            .sorted { lhs, rhs in
                if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var archivedEvents: [WatchSavedEvent] {
        events
            .filter { $0.isArchived() }
            .sorted { lhs, rhs in
                if lhs.archiveBoundary != rhs.archiveBoundary {
                    return (lhs.archiveBoundary ?? .distantPast) > (rhs.archiveBoundary ?? .distantPast)
                }
                return lhs.savedAt > rhs.savedAt
            }
    }

    var localization: WatchLocalization {
        WatchLocalization(language: language)
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let cached = defaults.string(forKey: Self.languageCacheKey),
           let cachedLanguage = WatchLanguage.resolve(cached) {
            language = cachedLanguage
        } else {
            language = WatchLanguage.preferred(from: preferredLanguages)
        }
        super.init()
    }

    func load() {
        guard !didLoad else { return }
        didLoad = true
        restoreCachedEvents()
        activateSession()
    }

    func requestSync() {
        guard WCSession.isSupported() else {
            syncNote = .syncUnavailable
            return
        }

        isSyncing = true
        syncNote = nil
        latestRequestAt = .now

        let session = WCSession.default
        if session.activationState != .activated {
            activateSession()
            scheduleRequestTimeout()
            return
        }

        let context = session.receivedApplicationContext
        applyPreferredLanguage(context[SyncKey.preferredLanguage] as? String)
        if let payload = context[SyncKey.payload] as? Data {
            apply(payload: payload)
            isSyncing = true
        }
        sendSyncRequestIfReachable()
        scheduleRequestTimeout()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func sendSyncRequestIfReachable() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else {
            isSyncing = false
            syncNote = .openPhoneToRefresh
            return
        }

        session.sendMessage([SyncKey.request: true], replyHandler: nil) { [weak self] _ in
            Task { @MainActor in
                guard self?.isSyncing == true else { return }
                self?.isSyncing = false
                self?.syncNote = .openPhoneToRefresh
            }
        }
    }

    private func scheduleRequestTimeout() {
        let requestDate = latestRequestAt
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self,
                  self.isSyncing,
                  self.latestRequestAt == requestDate else { return }
            self.isSyncing = false
            self.syncNote = .latestSavedOnWatch
        }
    }

    private func restoreCachedEvents() {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return }
        apply(payload: data, persist: false)
    }

    private func apply(payload: Data, persist: Bool = true) {
        guard let envelope = try? JSONDecoder().decode(WatchSavedEventsEnvelope.self, from: payload),
              envelope.schemaVersion == WatchSavedEventsEnvelope.currentSchemaVersion else {
            syncNote = .updatePhoneApp
            isSyncing = false
            return
        }

        applyPreferredLanguage(envelope.preferredLanguageCode)
        events = envelope.events
        totalSavedCount = envelope.totalSavedCount
        lastSyncedAt = envelope.syncedAt
        hasSynced = true
        isSyncing = false
        syncNote = nil
        if persist {
            defaults.set(payload, forKey: Self.cacheKey)
        }
    }

    private func applyPreferredLanguage(_ code: String?) {
        guard let code, let resolved = WatchLanguage.resolve(code) else { return }
        language = resolved
        defaults.set(resolved.rawValue, forKey: Self.languageCacheKey)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let payload = context[SyncKey.payload] as? Data
        let preferredLanguage = context[SyncKey.preferredLanguage] as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            let shouldRequestSync = self.isSyncing
            self.applyPreferredLanguage(preferredLanguage)
            if let payload {
                self.apply(payload: payload)
            }
            if activationState == .activated, error == nil, shouldRequestSync {
                self.isSyncing = true
                self.sendSyncRequestIfReachable()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let payload = applicationContext[SyncKey.payload] as? Data
        let preferredLanguage = applicationContext[SyncKey.preferredLanguage] as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyPreferredLanguage(preferredLanguage)
            if let payload {
                self.apply(payload: payload)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self, self.isSyncing, isReachable else { return }
            self.sendSyncRequestIfReachable()
        }
    }
}

private struct WatchSavedEventsEnvelope: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let syncedAt: Date
    let totalSavedCount: Int
    let events: [WatchSavedEvent]
    let preferredLanguageCode: String?
}

private struct WatchSavedEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let organization: String
    let details: String
    let category: String
    let city: String
    let region: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let deadline: String?
    let archiveBoundary: Date?
    let archived: Bool?
    let sourceURL: String?
    let registrationURL: String?
    let savedAt: Date

    var sortDate: Date {
        eventDate ?? deadlineDate ?? .distantFuture
    }

    var eventDate: Date? {
        parsedDate(from: startDate) ?? parsedDate(from: endDate)
    }

    var deadlineDate: Date? {
        parsedDate(from: deadline)
    }

    func placeLabel(localization: WatchLocalization) -> String {
        let place = [organization, city].filter { !$0.isEmpty }.joined(separator: " · ")
        return place.isEmpty ? localization.text(.locationInDetails) : place
    }

    func compactPlaceLabel(localization: WatchLocalization) -> String {
        [city, region, organization]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? localization.text(.eventDetails)
    }

    var locationLabel: String {
        if let address, !address.isEmpty { return address }
        return [city, region].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func timingLabel(localization: WatchLocalization) -> String {
        guard let date = eventDate ?? deadlineDate else { return localization.text(.timingInDetails) }
        let includesTime = primaryDateValue?.count != 10
        let formatter = DateFormatter()
        formatter.locale = localization.locale
        formatter.timeZone = Self.gtaTimeZone
        formatter.setLocalizedDateFormatFromTemplate(includesTime ? "EEEMMMdhm" : "EEEMMMd")
        return formatter.string(from: date)
    }

    func relativeTimingLabel(localization: WatchLocalization) -> String? {
        guard let date = eventDate, date > .now else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localization.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    func monthLabel(localization: WatchLocalization) -> String {
        guard let date = eventDate ?? deadlineDate else { return localization.text(.date) }
        let formatter = DateFormatter()
        formatter.locale = localization.locale
        formatter.timeZone = Self.gtaTimeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date).uppercased(with: localization.locale)
    }

    func dayLabel(localization: WatchLocalization) -> String {
        guard let date = eventDate ?? deadlineDate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = localization.locale
        formatter.timeZone = Self.gtaTimeZone
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter.string(from: date)
    }

    func isArchived(on now: Date = .now) -> Bool {
        if archived == true { return true }
        guard let archiveBoundary else { return false }
        return archiveBoundary < now
    }

    private var primaryDateValue: String? {
        if parsedDate(from: startDate) != nil { return startDate }
        if parsedDate(from: endDate) != nil { return endDate }
        return deadline
    }

    private func parsedDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = Self.gtaTimeZone
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }

    private static let gtaTimeZone = TimeZone(identifier: "America/Toronto") ?? TimeZone(secondsFromGMT: -18_000)!
}

private enum WatchRoute: Hashable {
    case event(WatchSavedEvent)
    case archive
}

private struct WatchContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.watchLocalization) private var localization
    @EnvironmentObject private var store: WatchOpportunityStore

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        header

                        if !store.hasSynced {
                            WatchEmptyState(
                                title: localization.text(.yourEventsTitle),
                                message: localization.text(.yourEventsMessage),
                                systemImage: "iphone.and.arrow.forward",
                                actionTitle: localization.text(.trySync),
                                action: store.requestSync
                            )
                        } else if store.events.isEmpty {
                            WatchEmptyState(
                                title: localization.text(.noSavedEvents),
                                message: localization.text(.noSavedEventsMessage),
                                systemImage: "bookmark",
                                actionTitle: localization.text(.checkAgain),
                                action: store.requestSync
                            )
                        } else {
                            savedEventContent
                        }

                        syncFooter
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case let .event(event):
                    WatchEventDetail(event: event)
                case .archive:
                    WatchArchiveView(events: store.archivedEvents)
                }
            }
            .task {
                store.load()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(localization.text(.myStemPlan), systemImage: "atom")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .foregroundStyle(WatchTheme.sun)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localization.text(.savedEvents))
                    .font(.title3.weight(.black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headerSubtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: store.requestSync) {
                ZStack {
                    if store.isSyncing, !reduceMotion {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: store.isSyncing ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.black))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(WatchTheme.lake, in: Circle())
            }
            .buttonStyle(.plain)
            .watchAccessibleControl()
            .accessibilityLabel(localization.text(.syncSavedFromPhone))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var headerSubtitle: String {
        if !store.hasSynced { return localization.text(.connectPhone) }
        let count = store.upcomingEvents.count
        if count == 1 {
            return localization.text(.eventComingOne)
        }
        return localization.text(.eventsComingMany, replacing: ["count": localization.number(count)])
    }

    @ViewBuilder
    private var savedEventContent: some View {
        if let next = store.upcomingEvents.first {
            VStack(spacing: 5) {
                NavigationLink(value: WatchRoute.event(next)) {
                    WatchNextEventCard(event: next)
                }
                .buttonStyle(.plain)
                .watchAccessibleControl()
                WatchOriginalSourceLink(event: next)
            }
        }

        if store.upcomingEvents.isEmpty {
            WatchEmptyState(
                title: localization.text(.nothingUpcoming),
                message: localization.text(.archiveStillAvailable),
                systemImage: "calendar.badge.checkmark"
            )
        } else if store.upcomingEvents.count > 1 {
            WatchSectionHeading(title: localization.text(.upcoming), systemImage: "calendar")
            ForEach(store.upcomingEvents.dropFirst()) { event in
                VStack(spacing: 5) {
                    NavigationLink(value: WatchRoute.event(event)) {
                        WatchEventRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .watchAccessibleControl()
                    WatchOriginalSourceLink(event: event)
                }
            }
        }

        NavigationLink(value: WatchRoute.archive) {
            WatchArchiveCard(count: store.archivedEvents.count)
        }
        .buttonStyle(.plain)
        .watchAccessibleControl()
    }

    @ViewBuilder
    private var syncFooter: some View {
        if let syncNote = store.syncNote {
            Label(localization.text(syncNote), systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } else if let lastSyncedAt = store.lastSyncedAt {
            Text(
                localization.text(
                    .synced,
                    replacing: ["value": localization.relativeDate(lastSyncedAt)]
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        if store.totalSavedCount > store.events.count {
            Text(
                localization.text(
                    .showingSavedEvents,
                    replacing: [
                        "shown": localization.number(store.events.count),
                        "total": localization.number(store.totalSavedCount)
                    ]
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct WatchSectionHeading: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)
            .padding(.top, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct WatchNextEventCard: View {
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !event.category.isEmpty {
                Text(event.category.uppercased(with: localization.locale))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 9) {
                WatchDateTile(event: event, inverted: true)

                Text(event.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Label(timingAndPlace, systemImage: event.relativeTimingLabel(localization: localization) == nil ? "mappin.and.ellipse" : "clock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [WatchTheme.coral, WatchTheme.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WatchTheme.ink.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            localization.text(
                .nextEventLabel,
                replacing: [
                    "title": event.title,
                    "time": event.timingLabel(localization: localization),
                    "place": event.placeLabel(localization: localization)
                ]
            )
        )
        .accessibilityHint(localization.text(.openEventDetails))
    }

    private var timingAndPlace: String {
        [
            event.relativeTimingLabel(localization: localization),
            event.compactPlaceLabel(localization: localization)
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct WatchEventRow: View {
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent

    var body: some View {
        HStack(spacing: 9) {
            WatchDateTile(event: event)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(event.timingLabel(localization: localization))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchTheme.lake)
                    .lineLimit(1)
                Text(event.placeLabel(localization: localization))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .watchSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(event.title). \(event.timingLabel(localization: localization)). \(event.placeLabel(localization: localization))"
        )
        .accessibilityHint(localization.text(.openEventDetails))
    }
}

private struct WatchDateTile: View {
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent
    var inverted = false

    var body: some View {
        VStack(spacing: 0) {
            Text(event.monthLabel(localization: localization))
                .font(.system(.caption2, design: .rounded, weight: .black))
                .minimumScaleFactor(0.75)
            Text(event.dayLabel(localization: localization))
                .font(.system(.title3, design: .rounded, weight: .black))
        }
        .foregroundStyle(WatchTheme.ink)
        .frame(width: 42, height: 46)
        .background(
            inverted ? AnyShapeStyle(WatchTheme.cream.opacity(0.88)) : AnyShapeStyle(WatchTheme.sun),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

private struct WatchArchiveCard: View {
    @Environment(\.watchLocalization) private var localization
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(WatchTheme.lavender)
                .frame(width: 34, height: 34)
                .background(WatchTheme.lavender.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.text(.eventArchive))
                    .font(.subheadline.weight(.bold))
                Text(
                    count == 1
                        ? localization.text(.pastSavedEventOne)
                        : localization.text(.pastSavedEventsMany, replacing: ["count": localization.number(count)])
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .watchSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint(localization.text(.openArchivedEvents))
    }
}

private struct WatchEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(WatchTheme.sun.opacity(0.24))
                    Image(systemName: systemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WatchTheme.coral)
                }
                .frame(width: 44, height: 44)

                Text(title)
                    .font(.headline.weight(.black))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.lake)
                    .watchAccessibleControl()
            }
        }
        .frame(maxWidth: .infinity)
        .watchSurface()
    }
}

private struct WatchArchiveView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.watchLocalization) private var localization
    let events: [WatchSavedEvent]

    var body: some View {
        ZStack {
            WatchTheme.background(for: colorScheme)
                .ignoresSafeArea()

            if events.isEmpty {
                ContentUnavailableView(
                    localization.text(.noArchivedEvents),
                    systemImage: "archivebox",
                    description: Text(localization.text(.archivedEventsDescription))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(events) { event in
                            VStack(spacing: 5) {
                                NavigationLink(value: WatchRoute.event(event)) {
                                    WatchArchivedEventRow(event: event)
                                }
                                .buttonStyle(.plain)
                                .watchAccessibleControl()
                                WatchOriginalSourceLink(event: event)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle(localization.text(.archive))
    }
}

private struct WatchOriginalSourceLink: View {
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent

    var body: some View {
        if let sourceURL = WatchExternalURL.make(from: event.sourceURL ?? event.registrationURL) {
            Link(destination: sourceURL) {
                Label(localization.text(.registrationDetails), systemImage: "arrow.up.right.square")
                    .font(.caption2.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.lake)
            .watchAccessibleControl()
        }
    }
}

private struct WatchArchivedEventRow: View {
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(WatchTheme.lavender)
            }
            Text(event.timingLabel(localization: localization))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Label(event.placeLabel(localization: localization), systemImage: "mappin")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .watchSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint(localization.text(.openEventDetails))
    }
}

private struct WatchEventDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.watchLocalization) private var localization
    let event: WatchSavedEvent

    var body: some View {
        ZStack {
            WatchTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    detailHeader
                    timingCard
                    locationCard
                    detailsCard
                    actions
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(localization.text(.eventDetailsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    event.isArchived() ? localization.text(.pastEvent) : localization.text(.savedEvent),
                    systemImage: event.isArchived() ? "archivebox.fill" : "bookmark.fill"
                )
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.90))
                Spacer()
                Image(systemName: "atom")
                    .foregroundStyle(.white.opacity(0.90))
            }

            Text(event.title)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)

            if !event.organization.isEmpty {
                Text(event.organization)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))
            }
        }
        .padding(12)
        .background(
            LinearGradient(colors: [WatchTheme.lake, WatchTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var timingCard: some View {
        WatchDetailCard(title: localization.text(.when), systemImage: "calendar.badge.clock", tint: WatchTheme.coral) {
            Text(event.timingLabel(localization: localization))
                .font(.subheadline.weight(.bold))
            if let deadline = event.deadlineDate, deadline > .now, deadline != event.eventDate {
                Text(
                    localization.text(
                        .applyBy,
                        replacing: ["date": localization.shortDateTime(deadline)]
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationCard: some View {
        WatchDetailCard(title: localization.text(.where), systemImage: "mappin.and.ellipse", tint: WatchTheme.lake) {
            if !event.locationLabel.isEmpty {
                Text(event.locationLabel)
                    .font(.subheadline.weight(.bold))
            } else {
                Text(localization.text(.checkFinalLocation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !event.city.isEmpty || !event.region.isEmpty {
                Text([event.city, event.region].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsCard: some View {
        WatchDetailCard(title: localization.text(.roomDetails), systemImage: "info.bubble.fill", tint: WatchTheme.lavender) {
            Text(event.details.isEmpty ? localization.text(.openRegistrationForDetails) : event.details)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let directionsURL = WatchMapsURL.make(for: event) {
            Link(destination: directionsURL) {
                Label(localization.text(.directionsInMaps), systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.navy)
            .watchAccessibleControl()
            .accessibilityHint(localization.text(.opensMapsHint))
        }

        if let detailsURL = WatchExternalURL.make(from: event.registrationURL ?? event.sourceURL) {
            Link(destination: detailsURL) {
                Label(localization.text(.registrationDetails), systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.lake)
            .watchAccessibleControl()
        }
    }
}

private struct WatchDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.black))
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface()
    }
}

private enum WatchMapsURL {
    static func make(for event: WatchSavedEvent) -> URL? {
        let destination: String
        if let latitude = event.latitude, let longitude = event.longitude {
            destination = "\(latitude),\(longitude)"
        } else if let address = event.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            destination = address
        } else {
            let fallback = [event.organization, event.city, event.region]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: ", ")
            guard !fallback.isEmpty else { return nil }
            destination = fallback
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        return components.url
    }
}

private enum WatchExternalURL {
    static func make(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }
}

private enum WatchTheme {
    static let ink = Color(red: 0.05, green: 0.07, blue: 0.08)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.87)
    static let paper = Color(red: 1.00, green: 0.99, blue: 0.93)
    static let lake = Color(red: 0.06, green: 0.44, blue: 0.52)
    static let navy = Color(red: 0.04, green: 0.18, blue: 0.33)
    static let sun = Color(red: 1.00, green: 0.73, blue: 0.12)
    static let coral = Color(red: 0.95, green: 0.34, blue: 0.22)
    static let orange = Color(red: 1.00, green: 0.49, blue: 0.19)
    static let lavender = Color(red: 0.60, green: 0.54, blue: 0.86)
    static let night = Color(red: 0.01, green: 0.04, blue: 0.16)
    static let nightCard = Color(red: 0.03, green: 0.14, blue: 0.29)

    static func background(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(colors: [night, navy, lake.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [cream, Color(red: 0.90, green: 0.98, blue: 1.00)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? nightCard.opacity(0.96) : paper
    }

    static func stroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? lake.opacity(0.75) : ink.opacity(0.12)
    }
}

private struct WatchSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                WatchTheme.surface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(WatchTheme.stroke(for: colorScheme), lineWidth: 1)
            }
    }
}

private extension View {
    func watchSurface() -> some View {
        modifier(WatchSurfaceModifier())
    }

    func watchAccessibleControl() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}
