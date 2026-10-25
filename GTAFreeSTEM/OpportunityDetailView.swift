import MapKit
import SwiftData
import SwiftUI
#if canImport(EventKitUI)
import EventKit
import EventKitUI
#endif

enum AppleMapsDestinationURL {
    static func make(
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String?,
        fallbackComponents: [String] = []
    ) -> URL? {
        let destination: String?
        if OpportunityCoordinate.isValid(latitude: latitude, longitude: longitude),
           let latitude,
           let longitude {
            destination = String(
                format: "%.6f,%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude,
                longitude
            )
        } else if let address = normalized(address) {
            destination = address
        } else {
            var seen = Set<String>()
            let parts = fallbackComponents.compactMap(normalized).filter { seen.insert($0).inserted }
            destination = parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        guard let destination else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        return components.url
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct OpportunityDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \SavedOpportunityRecord.savedAt, order: .reverse) private var savedRecords: [SavedOpportunityRecord]
    let opportunity: Opportunity
    @State private var saveErrorMessage: String?
    @State private var calendarPresented = false

    var body: some View {
        ZStack {
            StorybookBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    mapPreview
                    titleCard
                    details
                    actions
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.standard)
                .padding(.bottom, AppSpacing.large)
            }
        }
        .navigationTitle(session.text("details"))
        .navigationBarTitleDisplayMode(.inline)
#if canImport(EventKitUI)
#if DEBUG
        .task {
            if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-present-calendar") {
                calendarPresented = true
            }
        }
#endif
        .sheet(isPresented: $calendarPresented) {
            OpportunityCalendarEditor(
                opportunity: opportunity,
                title: session.title(for: opportunity),
                location: opportunity.address ?? session.city(for: opportunity),
                notes: session.fullDescription(for: opportunity)
            )
        }
#endif
    }

    private var isSaved: Bool {
        SavedOpportunityLibrary.isSaved(opportunity, in: savedRecords)
    }

    private var titleCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                StickerBadge(text: session.categoryName(for: opportunity), color: Brand.sun, systemImage: "star.fill")
                Text(session.title(for: opportunity))
                    .font(.title.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.organization(for: opportunity))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.lake)
                Text(session.fullDescription(for: opportunity))
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.body)
                    .foregroundStyle(Brand.outline(for: colorScheme))

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: AppSpacing.large, cornerRadius: AppRadius.feature)
    }

    private var mapPreview: some View {
        Group {
            if OpportunityCoordinate.isValid(
                latitude: opportunity.latitude,
                longitude: opportunity.longitude
            ), let latitude = opportunity.latitude, let longitude = opportunity.longitude {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                ))) {
                    Marker(
                        "\(session.title(for: opportunity)) · \(session.city(for: opportunity))",
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    )
                        .tint(Brand.lake)
                }
                .accessibilityLabel("\(session.text("map")): \(session.title(for: opportunity)), \(session.city(for: opportunity))")
                .frame(height: 220)
            } else {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Brand.selectionFill(for: colorScheme))
                    .frame(height: 180)
                    .overlay {
                        Label(session.city(for: opportunity), systemImage: "map")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Brand.outline(for: colorScheme))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
        }
        .shadow(color: Brand.deepOcean.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 12, x: 0, y: 6)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("details"), systemImage: "checklist")
            DetailFact(title: session.text("city"), value: "\(session.city(for: opportunity)), \(session.region(for: opportunity))", icon: "mappin.and.ellipse")
            DetailFact(title: session.text("ages"), value: "\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")", icon: "person.2")
            DetailFact(title: session.text("cost"), value: session.cost(for: opportunity), icon: "heart.fill")
            if let scheduleDateValue {
                DetailFact(title: session.text("date"), value: scheduleDateValue, icon: "calendar")
            }
            if let deadline = opportunity.deadline, shouldShowDeadline {
                DetailFact(title: session.text("deadline"), value: session.formattedLocalEventDateTime(deadline), icon: "alarm")
            }
            if opportunity.volunteerHoursEligible {
                DetailFact(title: session.text("pathway"), value: session.text("volunteerHours"), icon: "checkmark.seal")
            }
            if opportunity.coopEligible {
                DetailFact(title: session.text("pathway"), value: session.text("coop"), icon: "briefcase")
            }
            if !opportunity.language.isEmpty {
                DetailFact(title: session.text("languages"), value: opportunity.language.map(languageName).joined(separator: ", "), icon: "globe")
            }
            DetailFact(title: session.text("source"), value: opportunity.sourceUrl, icon: "link")
        }
        .cardSurface()
    }

    private var scheduleDateValue: String? {
        session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate)
    }

    private var shouldShowDeadline: Bool {
        LocalOpportunitySnapshot.hasDistinctRegistrationDeadline(opportunity)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            StorySectionTitle(text: session.text("details"), systemImage: "paperplane.fill")
            if let url = ExternalOpportunityURL.make(from: opportunity.registrationUrl ?? opportunity.sourceUrl) {
                Link(destination: url) {
                    Label(session.text(opportunity.registrationUrl == nil || opportunity.registrationUrl?.trimmingCharacters(in: .whitespacesAndNewlines) == opportunity.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines) ? "openProgramPage" : "registerApply"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .primary))
            }
#if canImport(EventKitUI)
            Button { calendarPresented = true } label: {
                Label(session.text("addToCalendar"), systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .secondary))
            .accessibilityIdentifier("opportunity-calendar")
#endif
            if let url = directionsURL {
                Link(destination: url) {
                    Label(session.text("directions"), systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .secondary))
            }
            Button {
                guard storageAccess.allowsPersistentChanges else { return }
                do {
                    _ = try SavedOpportunityLibrary.toggle(opportunity, in: modelContext)
                    saveErrorMessage = nil
                } catch {
                    saveErrorMessage = session.text("serverResponseInvalid")
                }
            } label: {
                Label(session.text(isSaved ? "saved" : "save"), systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
            .disabled(!storageAccess.allowsPersistentChanges)
            .accessibilityHint(
                session.text(
                    storageAccess.allowsPersistentChanges
                        ? "savedArchiveNote"
                        : "localStorageUnavailableMessage"
                )
            )

            if let saveErrorMessage {
                Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Brand.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    private var directionsURL: URL? {
        AppleMapsDestinationURL.make(
            latitude: opportunity.latitude,
            longitude: opportunity.longitude,
            address: opportunity.localizedAddress(language: session.language),
            fallbackComponents: [
                opportunity.localizedOrganization(language: session.language),
                opportunity.localizedCity(language: session.language),
                opportunity.localizedRegion(language: session.language)
            ]
        )
    }

    private func languageName(_ code: String) -> String {
        guard let language = AppLanguage.supportedLanguage(for: code) else { return code }
        return session.languageName(language)
    }
}

private struct DetailFact: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Brand.selectionFill(for: colorScheme), in: Circle())
                .foregroundStyle(Brand.lake)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

/// A draft for the person's system editor. No direct Calendar writes or reads.
struct NativeCalendarDraft {
    let start: Date?
    let end: Date?
    let allDay: Bool

    init(start: String?, end: String?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        func day(_ raw: String?) -> Date? {
            guard let raw, raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        if let startDay = day(start) {
            self.start = startDay
            self.allDay = true
            self.end = day(end).flatMap { $0 >= startDay ? calendar.date(byAdding: .day, value: 1, to: $0) : nil }
        } else {
            let startTime = start.flatMap { FeedFreshness.date(from: $0) }
            self.start = startTime
            self.allDay = false
            self.end = end.flatMap { FeedFreshness.date(from: $0) }.flatMap { value in
                startTime.flatMap { value > $0 ? value : nil }
            }
        }
    }
}

#if canImport(EventKitUI)
private struct OpportunityCalendarEditor: UIViewControllerRepresentable {
    let opportunity: Opportunity
    let title: String
    let location: String
    let notes: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        let store = EKEventStore()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        event.title = title
        event.location = location
        event.notes = "\(notes)\n\n\(opportunity.sourceUrl)"
        event.url = ExternalOpportunityURL.make(from: opportunity.sourceUrl)
        let draft = NativeCalendarDraft(start: opportunity.startDate, end: opportunity.endDate)
        event.isAllDay = draft.allDay
        event.timeZone = TimeZone(identifier: "America/Toronto")
        if let start = draft.start { event.startDate = start }
        if let end = draft.end { event.endDate = end }
        controller.event = event
        controller.editViewDelegate = context.coordinator
#if DEBUG
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-present-calendar") {
            Task { @MainActor in
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if controller.viewIfLoaded?.window != nil {
                        markCalendarReviewPresented()
                        break
                    }
                }
            }
        }
#endif
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { finish() }
    }
}
#if DEBUG
/// Records a displayed system-controller window only for the bounded CI sample smoke.
@MainActor
private func markCalendarReviewPresented() {
    let args = ProcessInfo.processInfo.arguments
    guard AppRuntime.isFrontendLayoutReview,
          let index = args.firstIndex(of: "-screenshot-ready-nonce"), args.indices.contains(index + 1),
          let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return }
    let nonce = args[index + 1]
    guard !nonce.isEmpty, nonce.count <= 200 else { return }
    FileHandle.standardOutput.write(Data(("GTA_CALENDAR_REVIEW_READY " + nonce + "\n").utf8))
    try? Data(nonce.utf8).write(to: cache.appendingPathComponent("gta-free-stem-calendar-review-ready"), options: .atomic)
}
#endif
#endif
