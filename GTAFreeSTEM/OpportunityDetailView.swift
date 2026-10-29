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
                    titleCard
                    keyFacts
                    providerAction
                    Text(session.fullDescription(for: opportunity))
                        .font(PortfolioTypography.body)
                        .foregroundStyle(Brand.outline(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    mapPreview
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ThemeToolbarButton(showLabel: false) } }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(session.categoryName(for: opportunity))
                .font(PortfolioTypography.caption.weight(.semibold))
                .foregroundStyle(Brand.lake)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.title(for: opportunity))
                .font(PortfolioTypography.title2.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(session.organization(for: opportunity))
                .font(PortfolioTypography.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyFacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLabels {
                if let ageGuide = OpportunityRow.ageGuideRange(for: opportunity) {
                    Text("\(session.text("ageGuide")): \(ageGuide)")
                }
                Label(opportunity.localizedCost(language: session.language), systemImage: "ticket")
                if opportunity.virtual {
                    Label(session.text("onlineActivity"), systemImage: "globe")
                } else {
                    Label(session.city(for: opportunity), systemImage: "mappin.and.ellipse")
                }
            }
            if let scheduleDateValue {
                Label(scheduleDateValue, systemImage: "calendar")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(PortfolioTypography.subheadline)
        .foregroundStyle(Brand.mutedText(for: colorScheme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var providerAction: some View {
        if let url = ExternalOpportunityURL.make(from: opportunity.registrationUrl ?? opportunity.sourceUrl) {
            Link(destination: url) {
                Label(session.text(opportunity.registrationUrl == nil || opportunity.registrationUrl?.trimmingCharacters(in: .whitespacesAndNewlines) == opportunity.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines) ? "openProgramPage" : "registerApply"), systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .primary))
        }
    }

    @ViewBuilder
    private var mapPreview: some View {
        if Self.canShowPhysicalMap(for: opportunity), let latitude = opportunity.latitude, let longitude = opportunity.longitude {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))) {
                Marker("\(session.title(for: opportunity)) · \(session.city(for: opportunity))",
                       coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    .tint(Brand.actionFill(for: colorScheme))
            }
            .accessibilityLabel("\(session.text("map")): \(session.title(for: opportunity)), \(session.city(for: opportunity))")
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
    }

    static func canShowPhysicalMap(for opportunity: Opportunity) -> Bool {
        !opportunity.virtual && OpportunityCoordinate.isValid(latitude: opportunity.latitude, longitude: opportunity.longitude)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            if !opportunity.virtual {
                DetailFact(title: session.text("city"), value: "\(session.city(for: opportunity)), \(session.region(for: opportunity))", icon: "mappin.and.ellipse")
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
            DetailFact(title: session.text("source"), value: opportunity.sourceUrl, icon: "link")
        }
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
                    .font(PortfolioTypography.footnote)
                    .foregroundStyle(Brand.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var directionsURL: URL? {
        Self.directionsURL(for: opportunity, language: session.language)
    }

    static func directionsURL(for opportunity: Opportunity, language: AppLanguage) -> URL? {
        guard !opportunity.virtual else { return nil }
        return AppleMapsDestinationURL.make(
            latitude: opportunity.latitude,
            longitude: opportunity.longitude,
            address: opportunity.localizedAddress(language: language),
            fallbackComponents: [
                opportunity.localizedOrganization(language: language),
                opportunity.localizedCity(language: language),
                opportunity.localizedRegion(language: language)
            ]
        )
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
                .font(PortfolioTypography.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Brand.selectionFill(for: colorScheme), in: Circle())
                .foregroundStyle(Brand.lake)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PortfolioTypography.caption.weight(.semibold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                Text(value)
                    .font(PortfolioTypography.subheadline)
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
