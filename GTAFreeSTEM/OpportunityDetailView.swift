import MapKit
import SwiftUI

struct OpportunityDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    let opportunity: Opportunity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapPreview
                Text(opportunity.title)
                    .font(.largeTitle.bold())
                Text(opportunity.organization)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(session.summary(for: opportunity))
                    .font(.body)
                if session.language != .en {
                    Text(session.text("translationNote"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                details
                actions
            }
            .padding()
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
            get: { store.errorMessage == APIError.accountRequired.localizedDescription || store.errorMessage == "Please sign in to use this feature." },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var mapPreview: some View {
        Group {
            if let latitude = opportunity.latitude, let longitude = opportunity.longitude {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                ))) {
                    Marker(opportunity.title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
                .frame(height: 220)
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.aqua.opacity(0.5), Brand.mint.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 180)
                    .overlay(Label(opportunity.city, systemImage: "map"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                Text(session.text("city")).bold()
                Text("\(opportunity.city), \(opportunity.region)")
            }
            GridRow {
                Text(session.text("ages")).bold()
                Text("\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")")
            }
            GridRow {
                Text(session.text("cost")).bold()
                Text(session.text("freeAccessible"))
            }
            if let startDate = opportunity.startDate {
                GridRow {
                    Text(session.text("date")).bold()
                    Text(startDate.prefix(10))
                }
            }
            if let deadline = opportunity.deadline {
                GridRow {
                    Text(session.text("deadline")).bold()
                    Text(deadline.prefix(10))
                }
            }
            if opportunity.volunteerHoursEligible {
                GridRow {
                    Text(session.text("pathway")).bold()
                    Text(session.text("volunteerHours"))
                }
            }
            if opportunity.coopEligible {
                GridRow {
                    Text(session.text("pathway")).bold()
                    Text(session.text("coop"))
                }
            }
            GridRow {
                Text(session.text("source")).bold()
                Text(opportunity.sourceUrl)
                    .lineLimit(2)
                    .font(.caption)
            }
            if !opportunity.language.isEmpty {
                GridRow {
                    Text(session.text("languages")).bold()
                    Text(opportunity.language.map(languageName).joined(separator: ", "))
                }
            }
        }
        .cardSurface()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let url = URL(string: opportunity.registrationUrl ?? opportunity.sourceUrl) {
                Link(destination: url) {
                    Label(session.text("registerApply"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if let url = directionsURL {
                Link(destination: url) {
                    Label(session.text("directions"), systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                Task { await store.save(opportunity, token: session.apiToken) }
            } label: {
                Label(session.text("save"), systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
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
