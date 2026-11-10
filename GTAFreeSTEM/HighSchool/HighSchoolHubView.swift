import SwiftUI

private enum SchoolHubDestination: Hashable {
    case pathway(String), listing(String), notebook
}

struct HighSchoolHubView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject var youth: HighSchoolHubStore
    let openActivities: () -> Void
    @State private var selectedAge = ""
    @State private var selectedGrade = ""
    @State private var selectedRegion = ""
    @State private var selectedDelivery = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("High School guide")
                        .font(PortfolioTypography.caption).foregroundStyle(Brand.mutedText(for: scheme))
                    if session.language != .en {
                        Text("This guide is currently in English. App navigation stays in your selected language.")
                            .font(PortfolioTypography.footnote).foregroundStyle(Brand.mutedText(for: scheme))
                            .accessibilityIdentifier("school-untranslated-notice")
                    }
                    Text("Find your next step.").font(PortfolioTypography.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Explore volunteering, learning, leadership and support. Check each provider’s requirements before committing.")
                        .font(PortfolioTypography.body)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach([YouthHub.Pathway.volunteer, .learning, .leadershipCareers, .funding], id: \.rawValue) { pathway in
                            NavigationLink(value: SchoolHubDestination.pathway(pathway.rawValue)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(pathway.artwork).resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                                    Text(pathway.title).font(PortfolioTypography.headline).fixedSize(horizontal: false, vertical: true)
                                    Text(pathway.summary).font(PortfolioTypography.subheadline).fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                                .cardSurface(cornerRadius: 18)
                            }
                            .buttonStyle(SpringPressButtonStyle())
                            .accessibilityIdentifier("school-pathway-\(pathway.rawValue)")
                        }
                    }
                    NavigationLink(value: SchoolHubDestination.notebook) {
                        Label("My completed hours", systemImage: "book.closed")
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(StoryButtonStyle(kind: .secondary)).accessibilityIdentifier("school-hours-notebook")
                    Text("Your notebook records actual completed time. It does not certify school credit.")
                        .font(PortfolioTypography.footnote).foregroundStyle(Brand.mutedText(for: scheme))
                    Button("Browse existing activities and saved filters", action: openActivities)
                        .buttonStyle(StoryButtonStyle(kind: .quiet))
                        .accessibilityIdentifier("school-open-activities")
                    if let error = youth.catalogueError {
                        Text(error).foregroundStyle(Brand.coral)
                        Button("Try reading the guide again") { Task { await youth.loadCatalogue() } }
                            .buttonStyle(StoryButtonStyle(kind: .secondary))
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(StorybookBackground())
            .navigationTitle("High School")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SchoolHubDestination.self) { destination in
                switch destination {
                case .pathway(let key):
                    if let pathway = YouthHub.Pathway(rawValue: key) { pathwayPage(pathway) }
                case .listing(let id):
                    if let listing = youth.listings.first(where: { $0.id == id }) {
                        YouthListingDetail(listing: listing, evaluation: evaluation(listing))
                    } else { Text("This record is not in the current reviewed guide.") }
                case .notebook: HoursNotebookView(youth: youth)
                }
            }
            .task { await youth.loadCatalogue() }
            .task(id: youth.listings.count) {
                guard AppLaunchConfiguration.isScreenshotCapture, !youth.listings.isEmpty else { return }
                await Task.yield()
                AppLaunchConfiguration.markScreenshotReady(youth.catalogueError == nil)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { youth.objectWillChange.send() }
            }
        }
        // Guide/editor copy is deliberately English; the outer app/footer keeps its own language.
        .environment(\.locale, Locale(identifier: "en_CA"))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("school-hub")
    }

    private func pathwayPage(_ pathway: YouthHub.Pathway) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(pathway.summary).font(PortfolioTypography.body)
                filterControls
                if pathway == .funding {
                    Text("Official funding guidance, not a placement, award offer or confirmed eligibility.").font(PortfolioTypography.callout)
                }
                if pathway == .volunteer {
                    let count = rows(pathway, kind: .role).filter { evaluation($0)?.verifiedFreeRoles == true }.count
                    Text(count == 0 ? "No individually verified free volunteer roles are listed in this guide. Programme intake, directories and guidance below are different routes." : "Check the requirements for each individually reviewed role.")
                        .font(PortfolioTypography.callout).accessibilityIdentifier("school-role-coverage")
                }
                listingSection("Reviewed no-fee programme intakes", rows: rows(pathway, kind: .program).filter { evaluation($0)?.verifiedFreePrograms == true })
                listingSection("Programmes to ask about or upcoming", rows: rows(pathway, kind: .program).filter { evaluation($0)?.verifiedFreePrograms != true })
                listingSection("Individual roles", rows: rows(pathway, kind: .role))
                listingSection("Places to look", rows: rows(pathway, kind: .providerDirectory))
                listingSection("Guidance and resources", rows: rows(pathway, kind: .resource))
                if !youth.listings.isEmpty && !youth.listings.contains(where: { $0.pathway == pathway && matches($0) }) {
                    Text("No reviewed records match these choices. Try clearing a filter. Unknown requirements still need provider confirmation.")
                }
                if youth.listings.isEmpty {
                    Text(youth.catalogueError ?? "Reading the reviewed guide…")
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(StorybookBackground()).navigationTitle(pathway.title)
    }
    private func evaluation(_ listing: YouthHub.Listing) -> YouthHub.Evaluation? {
        youth.evaluation(listing, age: Double(selectedAge), grade: Int(selectedGrade))
    }
    private func matches(_ listing: YouthHub.Listing) -> Bool {
        HighSchoolGuideSelection(age: Double(selectedAge), grade: Int(selectedGrade), region: selectedRegion,
                                 delivery: selectedDelivery).matches(listing, now: youth.timestamp)
    }
    private func costDescription(_ listing: YouthHub.Listing) -> String {
        switch evaluation(listing)?.costLabel {
        case "No fee evidenced": "Provider lists it as free"
        case "Required cost": "Required cost"
        default: "Check costs with provider"
        }
    }
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional guide filters").font(PortfolioTypography.headline)
            Text("Age and grade are independent; check provider rules for the summer before Grade 9. These choices stay in this guide and do not change your saved activity filters. Unspecified requirements still need confirmation.")
                .font(PortfolioTypography.footnote)
            Picker("Age", selection: $selectedAge) {
                Text("Any age").tag("")
                ForEach(12...25, id: \.self) { Text(String($0)).tag(String($0)) }
            }.accessibilityIdentifier("school-filter-age")
            Picker("Grade", selection: $selectedGrade) {
                Text("Any grade").tag("")
                ForEach(7...12, id: \.self) { Text("Grade \($0)").tag(String($0)) }
            }.accessibilityIdentifier("school-filter-grade")
            Picker("Region", selection: $selectedRegion) {
                Text("Any region").tag("")
                ForEach(Array(Set(youth.listings.flatMap { $0.regions ?? [] })).sorted(), id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("school-filter-region")
            Picker("Delivery", selection: $selectedDelivery) {
                Text("Any delivery").tag("")
                ForEach([YouthHub.Delivery.inPerson, .virtual, .hybrid], id: \.rawValue) { Text($0 == .virtual ? "Includes online activity" : $0 == .inPerson ? "Includes in-person activity" : "Mixed delivery—check format").tag($0.rawValue) }
            }.accessibilityIdentifier("school-filter-delivery")
            Button("Clear guide filters") { selectedAge = ""; selectedGrade = ""; selectedRegion = ""; selectedDelivery = "" }
                .buttonStyle(StoryButtonStyle(kind: .quiet))
        }.pickerStyle(.menu).cardSurface()
    }
    private func rows(_ pathway: YouthHub.Pathway, kind: YouthHub.ListingKind) -> [YouthHub.Listing] {
        youth.listings.filter { $0.pathway == pathway && $0.listingKind == kind && matches($0) }
    }
    @ViewBuilder private func listingSection(_ title: String, rows: [YouthHub.Listing]) -> some View {
        if !rows.isEmpty {
            Text(title).font(PortfolioTypography.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: SchoolHubDestination.listing(row.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(PortfolioTypography.headline)
                        Text(row.provider).font(PortfolioTypography.subheadline)
                        Text(row.listingKind == .providerDirectory ? "Directory · check individual roles" : evaluation(row)?.statusLabel ?? "Confirm with provider")
                            .font(PortfolioTypography.caption)
                        if row.listingKind == .program || row.listingKind == .role {
                            Text(costDescription(row)).font(PortfolioTypography.caption)
                        }
                        if let delivery = row.delivery, delivery != .unknown {
                            Text(delivery == .hybrid ? "Mixed delivery—check format" : delivery == .virtual ? "Includes online activity" : "Includes in-person activity")
                                .font(PortfolioTypography.caption)
                        }
                        if row.regions == nil || row.delivery == nil || row.delivery == .unknown {
                            Text("Location or delivery not specified; check the source.").font(PortfolioTypography.caption)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).cardSurface()
                }.buttonStyle(SpringPressButtonStyle()).accessibilityIdentifier("school-record-\(row.id)")
            }
        }
    }
}

private struct YouthListingDetail: View {
    @EnvironmentObject private var session: SessionStore
    let listing: YouthHub.Listing
    let evaluation: YouthHub.Evaluation?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(listing.title).font(PortfolioTypography.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(listing.provider).font(PortfolioTypography.headline)
                Text("Reviewed summary · confirm the provider’s current terms")
                    .font(PortfolioTypography.caption).foregroundStyle(Brand.mutedText(for: scheme))
                if session.language != .en {
                    Text("This provider summary is currently in English.").font(PortfolioTypography.footnote)
                }
                detail("Who it is for", listing.audience.original)
                if let residency = listing.audience.residency { detail("Residency", residency) }
                ForEach(listing.audience.restrictions ?? [], id: \.self) { Text($0).font(PortfolioTypography.body) }
                if listing.listingKind == .program || listing.listingKind == .role {
                    detail("Costs and necessary expenses", listing.cost.original)
                    ForEach(listing.cost.requiredCosts, id: \.description) { Text($0.description).font(PortfolioTypography.body) }
                    detail("Availability", (evaluation?.statusLabel ?? "Confirm with provider") + ". " + listing.availability.original)
                } else {
                    Text(listing.pathway == .funding ? "Funding guidance; no award or placement is promised." : "Directory or guidance; individual opportunities need their own checks.").font(PortfolioTypography.callout)
                }
                if let commitment = listing.commitmentOriginal { detail("Commitment", commitment) }
                if listing.listingKind == .program || listing.listingKind == .role || listing.hours.original != nil {
                    detail("School hours", listing.hours.original ?? "No specific hours are promised. Your school decides whether an activity qualifies.")
                }
                Text("Source checked: \(listing.checkedAt)").font(PortfolioTypography.caption)
                if evaluation?.evidenceCurrent != true {
                    Text("This review is not current. Confirm the details with the provider; availability and costs have not been refreshed.")
                        .foregroundStyle(Brand.coral)
                }
                if YouthHub.safeSourceURL(listing.sourceUrl), let url = URL(string: listing.sourceUrl) {
                    Link(destination: url) {
                        Text(listing.listingKind == .providerDirectory ? "Open provider directory" :
                             listing.listingKind == .program && evaluation?.applyNow == true ? "View programme intake" : "Check the provider’s source")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(StoryButtonStyle(kind: .primary))
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(StorybookBackground()).navigationTitle("Reviewed details").navigationBarTitleDisplayMode(.inline)
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(PortfolioTypography.headline).accessibilityAddTraits(.isHeader)
            Text(value).font(PortfolioTypography.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension YouthHub.Pathway {
    var title: String {
        switch self {
        case .volunteer: "Volunteer"
        case .learning: "Learn & create"
        case .leadershipCareers: "Leadership & careers"
        case .funding: "Scholarships & support"
        }
    }
    var summary: String {
        switch self {
        case .volunteer: "Understand commitments and find places to look for roles."
        case .learning: "Explore reviewed teen learning and creative programmes."
        case .leadershipCareers: "Find mentoring, leadership and career-planning routes."
        case .funding: "Read official guidance about awards, bursaries and aid."
        }
    }
    var artwork: String {
        switch self {
        case .volunteer: "gta_volunteer_illustration"
        case .learning: "gta_ideas_illustration"
        case .leadershipCareers: "gta_school_illustration"
        case .funding: "gta_support_illustration"
        }
    }
}
