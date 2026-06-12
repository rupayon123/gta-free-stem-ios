import MapKit
import SwiftData
import SwiftUI

enum BrowseSurface {
    case opportunities
    case highSchool

    var titleKey: String {
        switch self {
        case .opportunities: "navOpportunities"
        case .highSchool: "highSchool"
        }
    }

    var defaultMode: SearchMode {
        switch self {
        case .opportunities: .all
        case .highSchool: .highSchool
        }
    }

    var modes: [SearchMode] {
        switch self {
        case .opportunities:
            [.all]
        case .highSchool:
            [.highSchool, .volunteer, .coop, .mentorship]
        }
    }
}

struct BrowseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    let surface: BrowseSurface
    @StateObject private var locationManager = HuntLocationManager()
    @State private var filtersPresented = false
    @State private var displayMode: BrowseDisplayMode = .list

    init(surface: BrowseSurface = .opportunities) {
        self.surface = surface
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        searchControls
                        huntPanel

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
            .navigationTitle(session.text(surface.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $store.query, prompt: session.text("searchPlaceholder"))
            .onSubmit(of: .search) {
                Task { await store.refresh(cache: modelContext) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        filtersPresented = true
                    } label: {
                        Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        Task { await store.refresh(cache: modelContext, prioritized: true) }
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
                        Task { await store.refresh(cache: modelContext) }
                    },
                    reset: {
                        store.resetFilters()
                        Task { await store.refresh(cache: modelContext) }
                    }
                )
                .environmentObject(session)
            }
            .task {
                let didChangeMode = prepareSurface()
                if didChangeMode || store.opportunities.isEmpty {
                    await store.refresh(cache: modelContext)
                }
            }
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                store.useCurrentLocation(coordinate)
                Task { await store.refresh(cache: modelContext, prioritized: true) }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandLogoImage(size: surface == .highSchool ? 74 : 82)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(surface == .highSchool ? session.text("highSchool") : session.text("brand"))
                            .font(.title3.weight(.black))
                            .foregroundStyle(Brand.outline(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(surface == .highSchool ? highSchoolSummary : session.text("mission"))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Brand.mutedText(for: colorScheme))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if store.isLoading {
                        ProgressView()
                            .tint(Brand.coral)
                    }
                }

                FlowLabels {
                    StickerBadge(text: "\(store.activeCount) \(session.text("visible"))", color: Brand.sky, systemImage: "sparkle.magnifyingglass")
                    StickerBadge(text: session.text("freeShort"), color: Brand.sun, systemImage: "heart.fill")
                }

                Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardSurface(padding: 14, cornerRadius: 28)
    }

    private var searchControls: some View {
        VStack(spacing: 12) {
            if surface.modes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(surface.modes) { mode in
                            Button {
                                store.mode = mode
                                Task { await store.refresh(cache: modelContext) }
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
            }

            HStack(spacing: 10) {
                Button {
                    filtersPresented = true
                } label: {
                    Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .quiet))

                Button {
                    Task { await store.refresh(cache: modelContext, prioritized: true) }
                } label: {
                    Label("Hunt", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .primary))
            }

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

    private var huntPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: store.huntPhase.icon)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Brand.coral)
                    .symbolEffect(.pulse, value: store.isLoading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(surface == .highSchool ? "High school hunt engine" : "Search hunting engine")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                    Text(huntSubtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }

                Spacer()

                HuntRefreshButton(isLoading: store.isLoading) {
                    Task { await store.refresh(cache: modelContext, prioritized: true) }
                }
            }

            HStack(spacing: 10) {
                Button {
                    locationManager.requestOneShotLocation()
                } label: {
                    Label(locationButtonTitle, systemImage: "location.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .secondary))

                Button {
                    Task { await store.requestNotificationPermission() }
                } label: {
                    Label("Alerts", systemImage: "bell.badge.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .quiet))
            }

            FlowLabels {
                StickerBadge(text: radiusLabel, color: Brand.sky, systemImage: "scope")
                StickerBadge(text: store.filters.sort.label, color: Brand.lavender, systemImage: "arrow.up.arrow.down")
                if store.filters.includeNewFinds {
                    StickerBadge(text: "New finds included", color: Brand.sun, systemImage: "sparkles")
                }
                if store.newMatchesCount > 0 {
                    StickerBadge(text: "\(store.newMatchesCount) new", color: Brand.coral, systemImage: "burst.fill")
                }
            }

            if let message = locationManager.message ?? store.notificationStatusMessage {
                Text(message)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
        }
        .cardSurface(padding: 16, cornerRadius: 30)
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

    private var highSchoolSummary: String {
        "\(session.text("volunteerHours")) · \(session.text("coop")) · \(session.text("mentorship")) · \(session.text("leadership"))"
    }

    private var huntSubtitle: String {
        let area = store.filters.hasLocation ? "near your location" : (store.filters.city.isEmpty ? "across the GTA" : "in \(store.filters.city)")
        let status = store.isLoading ? "checking live sources" : store.huntPhase.title.lowercased()
        return "\(status) · \(area)"
    }

    private var locationButtonTitle: String {
        store.filters.hasLocation ? "Update nearby" : "Use nearby"
    }

    private var radiusLabel: String {
        store.filters.hasLocation ? "\(Int(store.filters.distanceKm)) km radius" : "Choose city or nearby"
    }

    @discardableResult
    private func prepareSurface() -> Bool {
        if !surface.modes.contains(store.mode) {
            store.mode = surface.defaultMode
            return true
        }
        return false
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
                if opportunity.status == "needs_review" || opportunity.isNewFind == true {
                    StickerBadge(text: "New find", color: Brand.sun, systemImage: "sparkles")
                }
                if let distanceKm = opportunity.distanceKm {
                    StickerBadge(text: String(format: "%.1f km", distanceKm), color: Brand.lavender, systemImage: "mappin.and.ellipse")
                }
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

                Section("Hunting") {
                    Picker("Sort results", selection: $filters.sort) {
                        ForEach(SearchSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    Toggle("Include new finds", isOn: $filters.includeNewFinds)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Distance radius: \(Int(filters.distanceKm)) km")
                            .font(.headline.weight(.bold))
                        Slider(value: $filters.distanceKm, in: 5...100, step: 5)
                    }
                    if filters.hasLocation {
                        Button("Clear nearby location") {
                            filters.latitude = nil
                            filters.longitude = nil
                            if filters.sort == .distance {
                                filters.sort = .date
                            }
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

private struct HuntRefreshButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isLoading ? Brand.coral : Brand.sun)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Circle().stroke(Brand.outline(for: colorScheme), lineWidth: 3)
                    }
                    .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 0, x: 4, y: 5)

                Image(systemName: isLoading ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                    .font(.title2.weight(.black))
                    .foregroundStyle(isLoading ? .white : Brand.ink)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(isLoading ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .spring(response: 0.3, dampingFraction: 0.55), value: isLoading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh hunt")
    }
}
