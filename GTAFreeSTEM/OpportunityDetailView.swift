import MapKit
import SwiftUI

struct OpportunityDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    let opportunity: Opportunity

    var body: some View {
        ZStack {
            StorybookBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mapPreview
                    titleCard
                    details
                    actions
                }
                .padding()
                .padding(.bottom, 24)
            }
        }
        .alert(session.text("saveNeedsAccountTitle"), isPresented: saveAlertBinding) {
            Button(session.text("ok"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(session.text("saveNeedsAccountMessage"))
        }
        .navigationTitle(session.text("details"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var saveAlertBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage == APIError.accountRequired.localizedDescription },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var titleCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                StickerBadge(text: opportunity.category, color: Brand.sun, systemImage: "star.fill")
                Text(opportunity.title)
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                Text(opportunity.organization)
                    .font(.title3.weight(.black))
                    .foregroundStyle(Brand.coral)
                Text(session.summary(for: opportunity))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                if session.language != .en {
                    Text(session.text("translationNote"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: 18, cornerRadius: 28)
    }

    private var mapPreview: some View {
        Group {
            if let latitude = opportunity.latitude, let longitude = opportunity.longitude {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                ))) {
                    Marker(opportunity.title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                        .tint(Brand.coral)
                }
                .frame(height: 220)
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.sky.opacity(0.72), Brand.moss.opacity(0.66)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 180)
                    .overlay {
                        Label(opportunity.city, systemImage: "map")
                            .font(.title3.weight(.black))
                            .foregroundStyle(Brand.ink)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Brand.outline(for: colorScheme), lineWidth: 3)
        }
        .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 0, x: 4, y: 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("details"), systemImage: "checklist")
            DetailFact(title: session.text("city"), value: "\(opportunity.city), \(opportunity.region)", icon: "mappin.and.ellipse")
            DetailFact(title: session.text("ages"), value: "\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")", icon: "person.2")
            DetailFact(title: session.text("cost"), value: session.text("freeAccessible"), icon: "heart.fill")
            if let startDate = opportunity.startDate {
                DetailFact(title: session.text("date"), value: String(startDate.prefix(10)), icon: "calendar")
            }
            if let deadline = opportunity.deadline {
                DetailFact(title: session.text("deadline"), value: String(deadline.prefix(10)), icon: "alarm")
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
        .cardSurface(padding: 18, cornerRadius: 28)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            StorySectionTitle(text: session.text("registerApply"), systemImage: "paperplane.fill")
            if let url = URL(string: opportunity.registrationUrl ?? opportunity.sourceUrl) {
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
                Task { await store.save(opportunity, token: session.apiToken) }
            } label: {
                Label(session.text("save"), systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
        }
        .cardSurface(padding: 18, cornerRadius: 28)
    }

    private var directionsURL: URL? {
        guard let address = opportunity.address?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "http://maps.apple.com/?q=\(address)")
    }

    private func languageName(_ code: String) -> String {
        guard let language = AppLanguage(rawValue: code) else { return code }
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
                .font(.headline.weight(.black))
                .frame(width: 30, height: 30)
                .background(Brand.sun, in: Circle())
                .overlay {
                    Circle().stroke(Brand.outline(for: colorScheme), lineWidth: 2)
                }
                .foregroundStyle(Brand.ink)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .textSelection(.enabled)
            }
        }
    }
}
