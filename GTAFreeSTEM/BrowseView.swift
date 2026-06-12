import MapKit
import SwiftUI

struct BrowseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @State private var filtersPresented = false
    @State private var displayMode: BrowseDisplayMode = .list

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        searchControls

                        if displayMode == .map {
                            opportunityMap
                        } else {
                            opportunityList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 112)
                }
            }
            .navigationTitle(session.text("browse"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $store.query, prompt: session.text("searchPlaceholder"))
            .onSubmit(of: .search) {
                Task { await store.refresh() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        filtersPresented = true
                    } label: {
                        Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label(session.text("refreshResearch"), systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
            .sheet(isPresented: $filtersPresented) {
                OpportunityFilterSheet(
                    filters: $store.filters,
                    apply: {
                        filtersPresented = false
                        Task { await store.refresh() }
                    },
                    reset: {
                        store.resetFilters()
                        Task { await store.refresh() }
                    }
                )
                .environmentObject(session)
            }
            .task {
                if store.opportunities.isEmpty {
                    await store.refresh()
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            StorybookWordmark()

            Text(session.text("mission"))
                .font(.title3.weight(.black))
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.outline(for: colorScheme))

            HStack(spacing: 10) {
                StickerBadge(text: "\(store.activeCount) \(session.text("visible"))", color: Brand.sky, systemImage: "sparkle.magnifyingglass")
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .tint(Brand.coral)
                }
            }

            Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))
        }
        .cardSurface(padding: 18, cornerRadius: 34)
    }

    private var searchControls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchMode.allCases) { mode in
                        Button {
                            store.mode = mode
                            Task { await store.refresh() }
                        } label: {
                            Text(session.text(mode.textKey))
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(store.mode == mode ? Brand.sun : Brand.raisedFill(for: colorScheme), in: Capsule())
                                .overlay {
                                    Capsule().stroke(Brand.outline(for: colorScheme), lineWidth: 2)
                                }
                                .foregroundStyle(Brand.outline(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityLabel(session.text("highSchool"))

            Picker(session.text("view"), selection: $displayMode) {
                ForEach(BrowseDisplayMode.allCases) { mode in
                    Text(session.text(mode.textKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(10)
        .background(Brand.cardFill(for: colorScheme).opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Brand.outline(for: colorScheme).opacity(0.45), lineWidth: 2)
        }
    }

    private var opportunityList: some View {
        LazyVStack(spacing: 12) {
            if store.opportunities.isEmpty {
                ContentUnavailableView(
                    session.text("noOpportunities"),
                    systemImage: "magnifyingglass",
                    description: Text(session.text("reset"))
                )
                .cardSurface()
            }

            ForEach(store.opportunities) { opportunity in
                NavigationLink(value: opportunity) {
                    OpportunityRow(opportunity: opportunity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var opportunityMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            StorySectionTitle(text: session.text("map"), systemImage: "map")
            Map {
                ForEach(store.opportunities.filter { $0.latitude != nil && $0.longitude != nil }) { opportunity in
                    Marker(
                        opportunity.title,
                        coordinate: CLLocationCoordinate2D(latitude: opportunity.latitude ?? 0, longitude: opportunity.longitude ?? 0)
                    )
                    .tint(Brand.coral)
                }
            }
            .frame(minHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Text(session.text("sourceDetails"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var localizedDataSource: String {
        store.dataSourceLabel == "Preview database" ? session.text("previewDatabase") : session.text("railsAPI")
    }

    private var background: some View {
        StorybookBackground()
    }
}

struct OpportunityRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StickerBadge(text: opportunity.category, color: categoryColor, systemImage: categoryIcon)
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.coral)
            }

            Text(opportunity.title)
                .font(.title3.weight(.black))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Text("\(opportunity.organization) · \(opportunity.city)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))

            FlowLabels {
                StickerBadge(text: "\(session.text("ages")) \(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")", color: Brand.sky, systemImage: "person.2")
                if opportunity.volunteerHoursEligible {
                    StickerBadge(text: session.text("volunteerHours"), color: Brand.moss, systemImage: "checkmark.seal")
                }
                if opportunity.coopEligible {
                    StickerBadge(text: session.text("coop"), color: Brand.lavender, systemImage: "briefcase")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16, cornerRadius: 26)
    }

    private var categoryIcon: String {
        if opportunity.coopEligible { return "briefcase.fill" }
        if opportunity.volunteerHoursEligible { return "checkmark.seal.fill" }
        if opportunity.category.localizedCaseInsensitiveContains("coding") { return "chevron.left.forwardslash.chevron.right" }
        if opportunity.category.localizedCaseInsensitiveContains("science") { return "atom" }
        return "star.fill"
    }

    private var categoryColor: Color {
        if opportunity.coopEligible { return Brand.lavender }
        if opportunity.volunteerHoursEligible { return Brand.moss }
        if opportunity.category.localizedCaseInsensitiveContains("science") { return Brand.sky }
        if opportunity.category.localizedCaseInsensitiveContains("competition") { return Brand.coral }
        return Brand.sun
    }
}

struct OpportunityFilterSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var filters: OpportunityFilters
    let apply: () -> Void
    let reset: () -> Void

    private let regions = ["Toronto", "Peel", "York", "Durham", "Halton"]
    private let cities = [
        "Toronto", "Mississauga", "Brampton", "Caledon", "Markham", "Richmond Hill", "Vaughan",
        "Aurora", "Newmarket", "Pickering", "Ajax", "Whitby", "Oshawa", "Clarington",
        "Oakville", "Burlington", "Milton", "Halton Hills"
    ]
    private let categories = [
        "STEM", "Coding & Robotics", "Science & Engineering", "AI & Digital Media",
        "Makerspace & Fabrication", "Camps", "Hackathons & Competitions", "Career & Mentorship",
        "Scholarships", "Newcomer & Settlement", "Family Learning", "Arts & Media",
        "Family STEM", "Volunteer Hours", "Co-op & SHSM", "Youth Leadership"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(session.text("region")) {
                    Picker(session.text("region"), selection: $filters.region) {
                        Text(session.text("allGta")).tag("All")
                        ForEach(regions, id: \.self) { region in
                            Text(region).tag(region)
                        }
                    }
                }

                Section(session.text("city")) {
                    Picker(session.text("city"), selection: $filters.city) {
                        Text(session.text("allCities")).tag("")
                        ForEach(cities, id: \.self) { city in
                            Text(city).tag(city)
                        }
                    }
                }

                Section(session.text("category")) {
                    Picker(session.text("category"), selection: $filters.category) {
                        Text(session.text("allCategories")).tag("All")
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }

                Section(session.text("age")) {
                    Picker(session.text("age"), selection: $filters.age) {
                        Text(session.text("any")).tag("")
                        ForEach(0...18, id: \.self) { age in
                            Text(age == 18 ? "18+" : "\(age)").tag("\(age)")
                        }
                    }
                }

                Section(session.text("programLanguage")) {
                    Picker(session.text("programLanguage"), selection: $filters.language) {
                        Text(session.text("any")).tag("all")
                        ForEach(AppLanguage.allCases) { language in
                            Text(session.languageName(language)).tag(language.rawValue)
                        }
                    }
                }

                Section(session.text("equity")) {
                    Toggle(session.text("black"), isOn: $filters.blackFocused)
                    Toggle(session.text("girls"), isOn: $filters.girlsFocused)
                    Toggle(session.text("indigenous"), isOn: $filters.indigenousFocused)
                    Toggle(session.text("leadership"), isOn: $filters.leadership)
                }
            }
            .scrollContentBackground(.hidden)
            .background(StorybookBackground())
            .tint(Brand.coral)
            .navigationTitle(session.text("filters"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.text("reset"), action: reset)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session.text("done"), action: apply)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
