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
                Text(opportunity.summary ?? opportunity.description)
                    .font(.body)
                details
                actions
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("City").bold()
                Text("\(opportunity.city), \(opportunity.region)")
            }
            GridRow {
                Text("Age").bold()
                Text("\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")")
            }
            GridRow {
                Text("Cost").bold()
                Text("Free and accessible")
            }
            if opportunity.volunteerHoursEligible {
                GridRow {
                    Text("Pathway").bold()
                    Text("Volunteer hours")
                }
            }
            if opportunity.coopEligible {
                GridRow {
                    Text("Pathway").bold()
                    Text("Co-op / SHSM")
                }
            }
        }
        .cardSurface()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let url = URL(string: opportunity.registrationUrl ?? opportunity.sourceUrl) {
                Link(destination: url) {
                    Label("Register / Apply", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                Task { await store.save(opportunity, token: session.apiToken) }
            } label: {
                Label("Save", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
