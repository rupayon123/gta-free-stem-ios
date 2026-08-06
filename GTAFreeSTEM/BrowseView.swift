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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    VStack(spacing: AppSpacing.standard) {
                        hero
                        searchControls

                        // A phone's first viewport should answer the question the user came
                        // to ask: what can I join? The full hunt controls remain one natural
                        // scroll below the live results, while larger layouts retain the
                        // research controls before the directory.
                        if prioritizesResultsOnCompactLayout {
                            resultsContent
                            huntPanel
                        } else {
                            huntPanel
                            resultsContent
                        }
                    }
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.standard)
                    .padding(.top, AppSpacing.small)
                    .padding(.bottom, 104)
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
                        Task { await store.refresh(cache: modelContext) }
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
                await preparePresentedSurface()
            }
            .onChange(of: session.language) { _, _ in
                Task { await preparePresentedSurface() }
            }
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                store.useCurrentLocation(coordinate)
                Task { await store.refresh(cache: modelContext) }
            }
        }
    }

    private var prioritizesResultsOnCompactLayout: Bool {
        horizontalSizeClass == .compact && displayMode == .list
    }

    @ViewBuilder
    private var resultsContent: some View {
        if displayMode == .map {
            opportunityMap
        } else {
            opportunityList
        }
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                BrandLogoImage(size: surface == .highSchool ? 54 : 60)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(surface == .highSchool ? session.text("highSchool") : session.text("brand"))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Brand.outline(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(surface == .highSchool ? highSchoolSummary : session.text("mission"))
                                .font(.footnote)
                                .foregroundStyle(Brand.mutedText(for: colorScheme))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if store.isLoading {
                            ProgressView()
                                .tint(Brand.lake)
                        }
                    }

                    FlowLabels {
                        StickerBadge(text: "\(store.activeCount) \(session.text("visible"))", color: Brand.sky, systemImage: "sparkle.magnifyingglass")
                        StickerBadge(text: session.text("freeShort"), color: Brand.sun, systemImage: "heart.fill")
                    }

                    Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                        .font(.caption)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                    if let lastUpdated = store.lastUpdated {
                        Label("\(session.text("date")): \(session.formattedDate(lastUpdated))", systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(Brand.mutedText(for: colorScheme))
                            .accessibilityIdentifier("feed-last-updated")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: AppSpacing.standard, cornerRadius: AppRadius.card)
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
                                    .lineLimit(1)
                            }
                            .buttonStyle(SelectionChipStyle(isSelected: store.mode == mode))
                            .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .accessibilityLabel(session.text("highSchool"))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    filterButton
                    huntButton
                }

                VStack(spacing: 10) {
                    filterButton
                    huntButton
                }
            }

            Picker(session.text("view"), selection: $displayMode) {
                ForEach(BrowseDisplayMode.allCases) { mode in
                    Text(session.text(mode.textKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .cardSurface(padding: AppSpacing.medium, cornerRadius: AppRadius.card)
    }

    private var filterButton: some View {
        Button {
            filtersPresented = true
        } label: {
            Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .quiet))
    }

    private var huntButton: some View {
        Button {
            Task { await store.refresh(cache: modelContext) }
        } label: {
            Label(session.text("hunt"), systemImage: "sparkle.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .primary))
        .disabled(store.isLoading)
    }

    private var huntPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                HuntActivityIcon(phase: store.huntPhase, isActive: store.isLoading, size: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(surface == .highSchool ? session.text("highSchoolHuntEngine") : session.text("searchHuntEngine"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                    Text(huntSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }

                Spacer(minLength: 8)
            }

            HuntRefreshButton(isLoading: store.isLoading, title: session.text("refreshResearch")) {
                Task { await store.refresh(cache: modelContext) }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    nearbyButton
                    alertsButton
                }

                VStack(spacing: 10) {
                    nearbyButton
                    alertsButton
                }
            }

            FlowLabels {
                StickerBadge(text: radiusLabel, color: Brand.sky, systemImage: "scope")
                StickerBadge(text: session.text(store.filters.sort.textKey), color: Brand.lavender, systemImage: "arrow.up.arrow.down")
                if store.filters.includeNewFinds {
                    StickerBadge(text: session.text("newFindsIncluded"), color: Brand.sun, systemImage: "sparkles")
                }
                if store.newMatchesCount > 0 {
                    StickerBadge(text: session.text("newCountShort").replacingOccurrences(of: "{count}", with: "\(store.newMatchesCount)"), color: Brand.coral, systemImage: "burst.fill")
                }
            }

            if let message = locationManager.message ?? store.notificationStatusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Brand.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    private var nearbyButton: some View {
        Button {
            locationManager.requestOneShotLocation()
        } label: {
            Label(locationButtonTitle, systemImage: "location.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .secondary))
    }

    private var alertsButton: some View {
        Button {
            Task { await store.requestNotificationPermission() }
        } label: {
            Label(session.text("alerts"), systemImage: "bell.badge.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .quiet))
    }

    private var opportunityList: some View {
        LazyVStack(spacing: 10) {
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
                ForEach(OpportunityMapProjection.pins(from: store.opportunities)) { opportunity in
                    Marker(
                        "\(session.title(for: opportunity)) · \(session.city(for: opportunity))",
                        coordinate: CLLocationCoordinate2D(latitude: opportunity.latitude ?? 0, longitude: opportunity.longitude ?? 0)
                    )
                    .tint(Brand.lake)
                }
            }
            .frame(minHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
            }
            .accessibilityLabel(mapAccessibilityLabel)
            .accessibilityHint(session.text("sourceDetails"))

            Text(session.text("sourceDetails"))
                .font(.caption)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
        }
        .cardSurface()
    }


    private var localizedDataSource: String {
        switch store.dataSourceLabel {
        case DataSource.publicLiveFeed:
            session.text("publicLiveFeed")
        case DataSource.previewDatabase:
            session.text("previewDatabase")
        case DataSource.savedAppCache:
            session.text("savedAppCache")
        }
    }

    private var mapAccessibilityLabel: String {
        "\(session.text("map")): \(store.opportunities.count) \(session.text("visible"))"
    }

    private var background: some View {
        StorybookBackground()
    }

    private var highSchoolSummary: String {
        "\(session.text("volunteerHours")) · \(session.text("coop")) · \(session.text("mentorship")) · \(session.text("leadership"))"
    }

    private var huntSubtitle: String {
        let area = store.filters.hasLocation ? session.text("nearYourLocation") : (store.filters.city.isEmpty ? session.text("acrossGTA") : session.text("inCity").replacingOccurrences(of: "{city}", with: store.filters.city))
        let status = store.isLoading ? session.text("checkingLiveSources") : session.text(store.huntPhase.titleKey)
        return "\(status) · \(area)"
    }

    private var locationButtonTitle: String {
        store.filters.hasLocation ? session.text("updateNearby") : session.text("useNearby")
    }

    private var radiusLabel: String {
        store.filters.hasLocation ? session.text("kmRadius").replacingOccurrences(of: "{km}", with: "\(Int(store.filters.distanceKm))") : session.text("chooseCityOrNearby")
    }

    @discardableResult
    private func prepareSurface() -> Bool {
        if !surface.modes.contains(store.mode) {
            store.mode = surface.defaultMode
            return true
        }
        return false
    }

    private func preparePresentedSurface() async {
        if AppLaunchConfiguration.isScreenshotCapture {
            // Configure the destination here as well as in ContentView so a
            // child-view task can never signal readiness before the requested
            // capture query and mode have been applied.
            if let screenshotQuery = AppLaunchConfiguration.screenshotQuery {
                store.query = screenshotQuery
            }
            store.mode = surface.defaultMode
            let isReady = await store.prepareScreenshotSnapshot()
            AppLaunchConfiguration.markScreenshotReady(isReady)
            return
        }

        _ = prepareSurface()
        await store.refreshIfStale(cache: modelContext)
    }
}

struct OpportunityRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StickerBadge(text: session.categoryName(for: opportunity), color: categoryColor, systemImage: categoryIcon)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .accessibilityHidden(true)
            }

            Text(session.title(for: opportunity))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(session.organization(for: opportunity)) · \(session.city(for: opportunity))")
                .font(.subheadline)
                .foregroundStyle(Brand.mutedText(for: colorScheme))

            if let scheduleText = session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate) {
                Label(scheduleText, systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLabels {
                StickerBadge(text: "\(session.text("ages")) \(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")", color: Brand.sky, systemImage: "person.2")
                if opportunity.status == "needs_review" || opportunity.isNewFind == true {
                    StickerBadge(text: session.text("newFind"), color: Brand.sun, systemImage: "sparkles")
                }
                if let distanceKm = opportunity.distanceKm {
                    StickerBadge(
                        text: session.text("distanceRadius").replacingOccurrences(of: "{km}", with: String(format: "%.1f", distanceKm)),
                        color: Brand.lavender,
                        systemImage: "mappin.and.ellipse"
                    )
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
        .cardSurface(padding: AppSpacing.standard, cornerRadius: AppRadius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(session.text("openDetailsHint"))
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

    private var accessibilityLabel: String {
        let ageRange = "\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")"
        var parts = [
            "\(session.text("details")): \(session.title(for: opportunity))",
            "\(session.text("category")): \(session.categoryName(for: opportunity))",
            "\(session.text("hostOrgName")): \(session.organization(for: opportunity))",
            "\(session.text("ages")) \(ageRange)",
            "\(session.text("city")) \(session.city(for: opportunity))"
        ]
        if opportunity.status == "needs_review" || opportunity.isNewFind == true {
            parts.append(session.text("newFind"))
        }
        if let scheduleText = session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate) {
            parts.append("\(session.text("date")): \(scheduleText)")
        }
        if let distanceKm = opportunity.distanceKm {
            parts.append(session.text("distanceRadius").replacingOccurrences(of: "{km}", with: String(format: "%.1f", distanceKm)))
        }
        if opportunity.volunteerHoursEligible {
            parts.append(session.text("volunteerHours"))
        }
        if opportunity.coopEligible {
            parts.append(session.text("coop"))
        }
        return parts.joined(separator: ". ")
    }
}

struct OpportunityFilterSheet: View {
    @Environment(\.colorScheme) private var colorScheme
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
                            Text(session.categoryName(category)).tag(category)
                        }
                    }
                }

                Section(session.text("age")) {
                    Picker(session.text("age"), selection: $filters.age) {
                        Text(session.text("any")).tag("")
                        ForEach(0...17, id: \.self) { age in
                            Text("\(age)").tag("\(age)")
                        }
                        Text(verbatim: "18+").tag("18+")
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

                Section(session.text("hunting")) {
                    Picker(session.text("sortResults"), selection: $filters.sort) {
                        ForEach(SearchSort.allCases) { sort in
                            Text(session.text(sort.textKey)).tag(sort)
                        }
                    }
                    Toggle(session.text("includeNewFinds"), isOn: $filters.includeNewFinds)
                    Toggle(session.text("volunteerHours"), isOn: $filters.volunteerHours)
                    Toggle(session.text("coop"), isOn: $filters.coop)
                    Toggle(session.text("mentorship"), isOn: $filters.mentorship)
                    Toggle(session.categoryName("Scholarships"), isOn: $filters.scholarships)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.text("distanceRadius").replacingOccurrences(of: "{km}", with: "\(Int(filters.distanceKm))"))
                            .font(.headline.weight(.semibold))
                        Slider(value: $filters.distanceKm, in: 5...100, step: 5)
                    }
                    if filters.hasLocation {
                        Button(session.text("clearNearbyLocation")) {
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
            .background(Brand.canvas(for: colorScheme))
            .tint(Brand.lake)
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
    let isLoading: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, value: isLoading)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .primary))
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}
