import Foundation
import SwiftUI
@preconcurrency import WatchConnectivity

@main
struct GTAFreeSTEMWatchApp: App {
    @StateObject private var store = WatchOpportunityStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
        }
    }
}

@MainActor
private final class WatchOpportunityStore: NSObject, ObservableObject, WCSessionDelegate {
    private enum SyncKey {
        static let payload = "savedEventsPayload"
        static let request = "requestSavedEvents"
    }

    private static let cacheKey = "watch-saved-events-v1"

    @Published private(set) var events = [WatchSavedEvent]()
    @Published private(set) var totalSavedCount = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var hasSynced = false
    @Published private(set) var isSyncing = false
    @Published private(set) var syncNote: String?

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            syncNote = "Watch sync is unavailable on this device."
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

        if let payload = session.receivedApplicationContext[SyncKey.payload] as? Data {
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
            syncNote = "Open GTA FREE STEM on your iPhone to refresh saved events."
            return
        }

        session.sendMessage([SyncKey.request: true], replyHandler: nil) { [weak self] _ in
            Task { @MainActor in
                guard self?.isSyncing == true else { return }
                self?.isSyncing = false
                self?.syncNote = "Open GTA FREE STEM on your iPhone to refresh saved events."
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
            self.syncNote = "Still showing the latest events saved on this watch."
        }
    }

    private func restoreCachedEvents() {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return }
        apply(payload: data, persist: false)
    }

    private func apply(payload: Data, persist: Bool = true) {
        guard let envelope = try? JSONDecoder().decode(WatchSavedEventsEnvelope.self, from: payload),
              envelope.schemaVersion == WatchSavedEventsEnvelope.currentSchemaVersion else {
            syncNote = "Update the iPhone app to sync saved events."
            isSyncing = false
            return
        }

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

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let payload = session.receivedApplicationContext[SyncKey.payload] as? Data
        Task { @MainActor [weak self] in
            guard let self else { return }
            let shouldRequestSync = self.isSyncing
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
        guard let payload = applicationContext[SyncKey.payload] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.apply(payload: payload)
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

    var placeLabel: String {
        let place = [organization, city].filter { !$0.isEmpty }.joined(separator: " · ")
        return place.isEmpty ? "Location in event details" : place
    }

    var compactPlaceLabel: String {
        [city, region, organization]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Event details"
    }

    var locationLabel: String {
        if let address, !address.isEmpty { return address }
        return [city, region].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var timingLabel: String {
        guard let date = eventDate ?? deadlineDate else { return "See event details for timing" }
        let includesTime = primaryDateValue?.count != 10
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = Self.gtaTimeZone
        formatter.setLocalizedDateFormatFromTemplate(includesTime ? "EEEMMMdhm" : "EEEMMMd")
        return formatter.string(from: date)
    }

    var relativeTimingLabel: String? {
        guard let date = eventDate, date > .now else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var monthLabel: String {
        guard let date = eventDate ?? deadlineDate else { return "DATE" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = Self.gtaTimeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date).uppercased()
    }

    var dayLabel: String {
        guard let date = eventDate ?? deadlineDate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .current
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
    @Environment(\.colorScheme) private var colorScheme
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
                                title: "Your events, at a glance",
                                message: "Open GTA FREE STEM on your iPhone, save an event, then sync it here.",
                                systemImage: "iphone.and.arrow.forward",
                                actionTitle: "Try sync",
                                action: store.requestSync
                            )
                        } else if store.events.isEmpty {
                            WatchEmptyState(
                                title: "No saved events",
                                message: "Save an event in the iPhone app and it will appear here, ready for your wrist.",
                                systemImage: "bookmark",
                                actionTitle: "Check again",
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
                Label("MY STEM PLAN", systemImage: "atom")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .foregroundStyle(WatchTheme.sun)
                    .lineLimit(1)

                Text("Saved events")
                    .font(.title3.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                Text(headerSubtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }

            Spacer(minLength: 0)

            Button(action: store.requestSync) {
                if store.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.black))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(WatchTheme.lake, in: Circle())
            .contentShape(Circle())
            .accessibilityLabel("Sync saved events from iPhone")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var headerSubtitle: String {
        if !store.hasSynced { return "Connect your iPhone" }
        let count = store.upcomingEvents.count
        return count == 1 ? "1 event coming up" : "\(count) events coming up"
    }

    @ViewBuilder
    private var savedEventContent: some View {
        if let next = store.upcomingEvents.first {
            NavigationLink(value: WatchRoute.event(next)) {
                WatchNextEventCard(event: next)
            }
            .buttonStyle(.plain)
        }

        if store.upcomingEvents.isEmpty {
            WatchEmptyState(
                title: "Nothing upcoming",
                message: "Your past saved events are still available in the archive.",
                systemImage: "calendar.badge.checkmark"
            )
        } else if store.upcomingEvents.count > 1 {
            WatchSectionHeading(title: "UPCOMING", systemImage: "calendar")
            ForEach(store.upcomingEvents.dropFirst()) { event in
                NavigationLink(value: WatchRoute.event(event)) {
                    WatchEventRow(event: event)
                }
                .buttonStyle(.plain)
            }
        }

        NavigationLink(value: WatchRoute.archive) {
            WatchArchiveCard(count: store.archivedEvents.count)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var syncFooter: some View {
        if let syncNote = store.syncNote {
            Label(syncNote, systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } else if let lastSyncedAt = store.lastSyncedAt {
            Text("Synced \(lastSyncedAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        if store.totalSavedCount > store.events.count {
            Text("Showing \(store.events.count) of \(store.totalSavedCount) saved events")
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
    let event: WatchSavedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !event.category.isEmpty {
                Text(event.category.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 9) {
                WatchDateTile(event: event, inverted: true)

                Text(event.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Label(timingAndPlace, systemImage: event.relativeTimingLabel == nil ? "mappin.and.ellipse" : "clock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
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
                .stroke(.white.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next event. \(event.title). \(event.timingLabel). \(event.placeLabel)")
        .accessibilityHint("Open event details")
    }

    private var timingAndPlace: String {
        [event.relativeTimingLabel?.capitalized, event.compactPlaceLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct WatchEventRow: View {
    let event: WatchSavedEvent

    var body: some View {
        HStack(spacing: 9) {
            WatchDateTile(event: event)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(event.timingLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchTheme.lake)
                    .lineLimit(1)
                Text(event.placeLabel)
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
        .accessibilityLabel("\(event.title). \(event.timingLabel). \(event.placeLabel)")
        .accessibilityHint("Open event details")
    }
}

private struct WatchDateTile: View {
    let event: WatchSavedEvent
    var inverted = false

    var body: some View {
        VStack(spacing: 0) {
            Text(event.monthLabel)
                .font(.system(.caption2, design: .rounded, weight: .black))
                .minimumScaleFactor(0.75)
            Text(event.dayLabel)
                .font(.system(.title3, design: .rounded, weight: .black))
        }
        .foregroundStyle(inverted ? .white : WatchTheme.ink)
        .frame(width: 42, height: 46)
        .background(
            inverted ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(WatchTheme.sun),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

private struct WatchArchiveCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(WatchTheme.lavender)
                .frame(width: 34, height: 34)
                .background(WatchTheme.lavender.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Event archive")
                    .font(.subheadline.weight(.bold))
                Text(count == 1 ? "1 past saved event" : "\(count) past saved events")
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
        .accessibilityHint("Open archived events")
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
            }
        }
        .frame(maxWidth: .infinity)
        .watchSurface()
    }
}

private struct WatchArchiveView: View {
    @Environment(\.colorScheme) private var colorScheme
    let events: [WatchSavedEvent]

    var body: some View {
        ZStack {
            WatchTheme.background(for: colorScheme)
                .ignoresSafeArea()

            if events.isEmpty {
                ContentUnavailableView(
                    "No archived events",
                    systemImage: "archivebox",
                    description: Text("Saved events appear here after their date and time pass.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(events) { event in
                            NavigationLink(value: WatchRoute.event(event)) {
                                WatchArchivedEventRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Archive")
    }
}

private struct WatchArchivedEventRow: View {
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
            Text(event.timingLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Label(event.placeLabel, systemImage: "mappin")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .watchSurface()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open archived event details")
    }
}

private struct WatchEventDetail: View {
    @Environment(\.colorScheme) private var colorScheme
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
        .navigationTitle("Event details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(event.isArchived() ? "PAST EVENT" : "SAVED EVENT", systemImage: event.isArchived() ? "archivebox.fill" : "bookmark.fill")
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
        WatchDetailCard(title: "WHEN", systemImage: "calendar.badge.clock", tint: WatchTheme.coral) {
            Text(event.timingLabel)
                .font(.subheadline.weight(.bold))
            if let deadline = event.deadlineDate, deadline > .now, deadline != event.eventDate {
                Text("Apply by \(deadline.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationCard: some View {
        WatchDetailCard(title: "WHERE", systemImage: "mappin.and.ellipse", tint: WatchTheme.lake) {
            if !event.locationLabel.isEmpty {
                Text(event.locationLabel)
                    .font(.subheadline.weight(.bold))
            } else {
                Text("Check the event details for the final room or meeting point.")
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
        WatchDetailCard(title: "ROOM & DETAILS", systemImage: "info.bubble.fill", tint: WatchTheme.lavender) {
            Text(event.details.isEmpty ? "Open the registration page for room and arrival details." : event.details)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let directionsURL = WatchMapsURL.make(for: event) {
            Link(destination: directionsURL) {
                Label("Directions in Maps", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.coral)
            .accessibilityHint("Opens Apple Maps with directions to this event")
        }

        if let detailsURL = WatchExternalURL.make(from: event.registrationURL ?? event.sourceURL) {
            Link(destination: detailsURL) {
                Label("Registration details", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.lake)
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
}
