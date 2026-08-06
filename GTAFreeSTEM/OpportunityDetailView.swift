import MapKit
import SwiftData
import SwiftUI

enum AppleMapsDestinationURL {
    static func make(
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String?,
        fallbackComponents: [String] = []
    ) -> URL? {
        let destination: String?
        if let latitude,
           let longitude,
           latitude.isFinite,
           longitude.isFinite,
           (-90...90).contains(latitude),
           (-180...180).contains(longitude) {
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
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \SavedOpportunityRecord.savedAt, order: .reverse) private var savedRecords: [SavedOpportunityRecord]
    let opportunity: Opportunity
    @State private var saveErrorMessage: String?

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
                Text(session.summary(for: opportunity))
                    .font(.body)
                    .foregroundStyle(Brand.outline(for: colorScheme))
                if session.language != .en, opportunity.hasTranslation(for: session.language) {
                    Text(session.text("translationNote"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: AppSpacing.large, cornerRadius: AppRadius.feature)
    }

    private var mapPreview: some View {
        Group {
            if let latitude = opportunity.latitude, let longitude = opportunity.longitude {
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
                DetailFact(title: session.text("deadline"), value: session.formattedEventDateTime(deadline), icon: "alarm")
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
            StorySectionTitle(text: session.text("registerApply"), systemImage: "paperplane.fill")
            if let url = ExternalOpportunityURL.make(from: opportunity.registrationUrl ?? opportunity.sourceUrl) {
                Link(destination: url) {
                    Label(session.text("registerApply"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .primary))
            }
            if let url = directionsURL {
                Link(destination: url) {
                    Label(session.text("directions"), systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .secondary))
            }
            Button {
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
            .accessibilityHint(session.text("savedArchiveNote"))

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
        let language = AppLanguage.normalized(code)
        if language == .en && code != AppLanguage.en.rawValue { return code }
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
