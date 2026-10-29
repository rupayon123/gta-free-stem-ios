import MapKit
import SwiftData
import SwiftUI

enum BrowseSurface {
    case opportunities
    case highSchool

    var titleKey: String {
        switch self {
        case .opportunities: "browse"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    let surface: BrowseSurface
    @StateObject private var locationManager = HuntLocationManager()
    @State private var saveSearchPresented = false
    @State private var filtersPresented = false
    @State private var websiteUnavailable = false
    @State private var displayMode: BrowseDisplayMode = .list
    @State private var selectedVenueID: String?
    @State private var navigationPath: [Opportunity] = []
    @StateObject private var mapProjection = OpportunityMapPresentation()
    @State private var mapResetRevision = 0
    @State private var coincidentVenueIDs: Set<String> = []
    @FocusState private var searchFocused: Bool

    init(surface: BrowseSurface = .opportunities) {
        self.surface = surface
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-review-map") {
            _displayMode = State(initialValue: .map)
        }
#endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                background

                ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: AppSpacing.standard) {
                        queryField
                        if displayMode == .list { hero }
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
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: selectedVenueID) { _, newID in
                    if newID != nil { scrollProxy.scrollTo("map-selected-location", anchor: .top) }
                }
                .onChange(of: coincidentVenueIDs) { _, ids in
                    if !ids.isEmpty { scrollProxy.scrollTo("map-selected-location", anchor: .top) }
                }
                }
            }
            .navigationTitle(session.text(surface.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        filtersPresented = true
                    } label: {
                        Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        Task { await store.refresh(cache: persistenceContext) }
                    } label: {
                        Label(session.text("refreshResearch"), systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
            .sheet(isPresented: $saveSearchPresented) {
                SaveNamedSearchSheet().environmentObject(session).environmentObject(store)
                    .environment(\.layoutDirection, session.language.layoutDirection)
                    .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
                    .dynamicTypeSize(dynamicTypeSize)
            }
            .sheet(isPresented: $filtersPresented) {
                OpportunityFilterSheet(
                    filters: $store.filters,
                    surface: surface,
                    apply: {
                        filtersPresented = false
                        Task { await store.refresh(cache: persistenceContext) }
                    },
                    reset: {
                        store.resetFilters()
                    }
                )
                .environmentObject(session)
                .environment(\.layoutDirection, session.language.layoutDirection)
                .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
            }
            .task {
                await preparePresentedSurface()
#if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if AppRuntime.isFrontendLayoutReview,
                   arguments.contains("-review-save-search") || arguments.contains("-review-update-search") {
                    if arguments.contains("-review-update-search") {
                        await store.prepareNamedSearchLayoutReview()
                        if let first = store.savedSearches.first { _ = await store.openNamedSearch(first.id) }
                    }
                    saveSearchPresented = true
                }
#endif
            }
            .onChange(of: session.language) { _, _ in
                Task { await preparePresentedSurface() }
            }
            .onReceive(store.$opportunities) { records in
                mapProjection.prepare(records)
            }
            .onAppear { mapProjection.resumeIfInterrupted(store.opportunities) }
            .onDisappear {
                searchFocused = false
                mapProjection.cancel()
            }
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                store.useCurrentLocation(coordinate)
                Task { await store.refresh(cache: persistenceContext) }
            }
        }
    }

    private var prioritizesResultsOnCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var queryField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .accessibilityHidden(true)

            TextField(session.text("searchPlaceholder"), text: $store.query)
                .font(PortfolioTypography.body)
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityLabel(session.text("search"))
                .accessibilityHint(session.text("searchPlaceholder"))
                .accessibilityIdentifier("browse-query")
                .onSubmit {
                    searchFocused = false
                    Task { await store.refresh(cache: persistenceContext) }
                }

            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.text("clearSearch"))
                .accessibilityIdentifier("browse-query-clear")
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .modifier(StoryFieldModifier())
    }

    @ViewBuilder
    private var resultsContent: some View {
        if store.opportunities.isEmpty {
            emptyOpportunityState
        } else if displayMode == .map {
            opportunityMap
        } else {
            opportunityList
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandLogoImage(size: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(OpportunityResultCountText.string(store.activeCount, language: session.language))
                    .font(PortfolioTypography.headline.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                    .font(PortfolioTypography.caption)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let lastUpdated = store.lastUpdated {
                    Text("\(session.text("date")): \(session.formattedDate(lastUpdated))")
                        .font(PortfolioTypography.caption)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feed-last-updated")
                }
            }
            Spacer(minLength: 4)
            if store.isLoading { ProgressView().tint(Brand.actionFill(for: colorScheme)) }
            ThemeToolbarButton(showLabel: false)
        }
        .padding(.vertical, 4)
    }

    private var searchControls: some View {
        VStack(spacing: 12) {
            if surface.modes.count > 1 {
                if horizontalSizeClass == .compact {
                    WrappingHStack(
                        horizontalSpacing: 8,
                        verticalSpacing: 8,
                        layoutDirection: layoutDirection
                    ) {
                        modeButtons
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 8) {
                        modeButtons
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    filterButton
                    huntButton
                }
            } else {
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
            }

            Picker(session.text("view"), selection: $displayMode) {
                ForEach(BrowseDisplayMode.allCases) { mode in
                    Text(session.text(mode.textKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.bottom, 2)
    }

    private var modeButtons: some View {
        ForEach(surface.modes) { mode in
            Button {
                store.mode = mode
                Task { await store.refresh(cache: persistenceContext) }
            } label: {
                Text(modeTitle(for: mode))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(SelectionChipStyle(isSelected: store.mode == mode))
            .accessibilityLabel("\(session.text(surface.titleKey)): \(modeTitle(for: mode))")
            .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
        }
    }

    private func modeTitle(for mode: SearchMode) -> String {
        mode == surface.defaultMode ? session.text("all") : session.text(mode.textKey)
    }

    private var filterButton: some View {
        Button {
            filtersPresented = true
        } label: {
            Label(session.text("filters"), systemImage: store.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .quiet))
    }

    private var huntButton: some View {
        Button {
            Task { await store.refresh(cache: persistenceContext) }
        } label: {
            Label(session.text("hunt"), systemImage: "sparkle.magnifyingglass")
                .fixedSize(horizontal: true, vertical: true)
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
                        .font(PortfolioTypography.headline.weight(.semibold))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                    Text(huntSubtitle)
                        .font(PortfolioTypography.subheadline)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }

                Spacer(minLength: 8)
            }

            HuntRefreshButton(isLoading: store.isLoading, title: session.text("refreshResearch")) {
                Task { await store.refresh(cache: persistenceContext) }
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
                    .font(PortfolioTypography.footnote)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(PortfolioTypography.footnote)
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
        LazyVStack(spacing: 0) {
            ForEach(store.opportunities) { opportunity in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: opportunity) {
                        OpportunityRow(opportunity: opportunity)
                    }
                    .buttonStyle(.plain)

                    if let sourceURL = ExternalOpportunityURL.make(from: opportunity.sourceUrl) {
                        Divider()
                            .overlay(Brand.surfaceStroke(for: colorScheme))

                        Link(destination: sourceURL) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Label(session.text("source"), systemImage: "arrow.up.right.square")
                                    .font(PortfolioTypography.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Text(session.text("openProgramPage"))
                                    .font(PortfolioTypography.caption)
                                    .multilineTextAlignment(.trailing)
                            }
                            .foregroundStyle(Brand.lake)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(session.text("source")): \(session.title(for: opportunity))")
                        .accessibilityHint(session.text("sourceDetails"))
                    }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    @ViewBuilder
    private var emptyOpportunityState: some View {
        if store.isLoading {
            ContentUnavailableView(session.text("huntingNow"), systemImage: "hourglass")
                .padding(.vertical, AppSpacing.large)
        } else {
            ContentUnavailableView {
                Label(
                    store.errorMessage ?? session.text("noOpportunities"),
                    systemImage: store.errorMessage == nil ? "magnifyingglass" : "wifi.exclamationmark"
                )
            } actions: {
                if hasResettableSearch {
                    Button(session.text("reset"), action: resetEmptySearch)
                        .buttonStyle(.bordered)
                }

                if store.errorMessage != nil {
                    Button {
                        openURL(Self.onlineBrowseURL) { accepted in
                            websiteUnavailable = !accepted
                        }
                    } label: {
                        Label(session.text("browseOnline"), systemImage: "arrow.up.right.square")
                    }
                    .accessibilityHint(session.text("opensWebsite"))
                    .accessibilityIdentifier("browse-online")
                    Text(session.text("opensWebsite"))
                        .font(PortfolioTypography.caption)
                    if websiteUnavailable {
                        Text(session.text("websiteUnavailable"))
                            .foregroundStyle(Brand.coral)
                    }
                }

                if store.errorMessage != nil || !hasResettableSearch {
                    Button(session.text("retry"), action: retryEmptySearch)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, AppSpacing.large)
        }
    }

    static let onlineBrowseURL = URL(string: "https://gta-free-stem.pages.dev/opportunities/")!

    private var hasResettableSearch: Bool {
        !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            store.filters.hasActiveFilters ||
            store.mode != surface.defaultMode
    }

    private func resetEmptySearch() {
        // Reset every constraint that can hide an otherwise valid listing,
        // including a one-shot nearby coordinate retained inside the filters.
        store.query = ""
        store.resetFilters()
        store.mode = surface.defaultMode
        Task { await store.refresh(cache: persistenceContext) }
    }

    private func retryEmptySearch() {
        // A retry is an explicit user request and should bypass only the short
        // anti-thrashing window; OpportunityStore still prevents concurrency.
        Task { await store.refresh(cache: persistenceContext, force: true) }
    }

    private var mapVenues: [OpportunityMapVenue] {
        mapProjection.snapshot.venues
    }

    private var opportunityMap: some View {
        let venues = mapVenues
        let mappedCount = mapProjection.snapshot.mappedCount
        let selectedVenues = venues.filter { $0.id == selectedVenueID || coincidentVenueIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            StorySectionTitle(text: session.text("map"), systemImage: "map")
            if mapProjection.isPreparing && venues.isEmpty {
                ProgressView(session.text("preparingOpportunities"))
            } else if venues.isEmpty {
                ContentUnavailableView(session.text("mapNoLocations"), systemImage: "mappin.slash")
            } else {
                Text(session.text("mapLocationCount")
                    .replacingOccurrences(of: "{locations}", with: "\(venues.count)")
                    .replacingOccurrences(of: "{count}", with: "\(mappedCount)"))
                    .font(PortfolioTypography.subheadline.weight(.semibold))
                ClusteredOpportunityMap(
                    snapshot: mapProjection.snapshot,
                    revision: mapProjection.revision,
                    resetRevision: mapResetRevision,
                    selectedVenueID: $selectedVenueID,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion,
                    language: session.language,
                    venueTitle: venueTitle,
                    clusterTitle: { count, events in
                        session.text("mapLocationCount")
                            .replacingOccurrences(of: "{locations}", with: "\(count)")
                            .replacingOccurrences(of: "{count}", with: "\(events)")
                    },
                    selectCoincidentVenues: { ids in coincidentVenueIDs = Set(ids) },
                    clearCoincidentVenues: { coincidentVenueIDs = [] }
                )
                .frame(height: horizontalSizeClass == .compact ? 340 : 520)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
                }
                .accessibilityLabel(mapAccessibilityLabel)
                .accessibilityHint(session.text("mapLocationsHint"))
                .accessibilityIdentifier("opportunity-map")
                .onAppear { updateMap(for: venues) }
                .onChange(of: mapProjection.revision) { _, _ in
                    coincidentVenueIDs.formIntersection(Set(venues.map(\.id)))
                    updateMap(for: venues)
                }

                Button { updateMap(for: venues, clearSelection: true) } label: {
                    Label(session.text("mapShowLocations"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("map-show-locations")
                Text(session.text("mapLocationsHint"))
                    .font(PortfolioTypography.caption)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }

            if !selectedVenues.isEmpty {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedVenues) { selected in
                        Text(selected.address)
                            .font(PortfolioTypography.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(selected.opportunities) { opportunity in
                            NavigationLink(value: opportunity) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title(for: opportunity)).font(PortfolioTypography.subheadline.weight(.semibold))
                                        Text(session.organization(for: opportunity)).font(PortfolioTypography.caption)
                                        if let schedule = session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate) {
                                            Text(schedule)
                                                .font(PortfolioTypography.caption)
                                                .foregroundStyle(Brand.mutedText(for: colorScheme))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(session.text("details"))
                            .accessibilityIdentifier("map-opportunity-\(opportunity.id)")
                            Divider()
                        }
                    }
                }
                .id("map-selected-location")
                .cardSurface(padding: AppSpacing.medium)
                .accessibilityIdentifier("map-selected-location")
            }

            if mappedCount < store.opportunities.count {
                Text(session.text("mapMissingLocations").replacingOccurrences(of: "{count}", with: "\(store.opportunities.count - mappedCount)"))
                    .font(PortfolioTypography.footnote)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            Button { displayMode = .list } label: {
                Label(session.text("list"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
            .accessibilityIdentifier("map-list-fallback")
        }
        .cardSurface()
    }

    private func venueTitle(_ venue: OpportunityMapVenue) -> String {
        venue.opportunities.count == 1
            ? session.title(for: venue.opportunities[0])
            : "\(venue.opportunities.count) \(session.text("navOpportunities")) · \(session.city(for: venue.opportunities[0]))"
    }

    private func focusMap(on venue: OpportunityMapVenue) {
        selectedVenueID = venue.id
    }

    private func updateMap(for venues: [OpportunityMapVenue], clearSelection: Bool = false) {
        if clearSelection || !venues.contains(where: { $0.id == selectedVenueID }) { selectedVenueID = nil }
        coincidentVenueIDs.formIntersection(Set(venues.map(\.id)))
        if clearSelection { coincidentVenueIDs = [] }
        guard !venues.isEmpty else { return }
        mapResetRevision &+= 1
#if DEBUG
        // Isolated runtime review can open a real selected-location state.
        // It never fabricates a venue or mutates the feed, saved state or loader.
        let arguments = ProcessInfo.processInfo.arguments
        if !clearSelection, arguments.contains("-review-map-selected"), let first = venues.first(where: { $0.opportunities.count > 1 }) ?? venues.first {
            selectedVenueID = first.id
            focusMap(on: first)
            if arguments.contains("-review-map-detail"), let opportunity = first.opportunities.first, navigationPath.isEmpty {
                navigationPath = [opportunity]
            }
        }
        if !clearSelection, arguments.contains("-review-virtual-detail"),
           let opportunity = store.opportunities.first(where: { $0.virtual }), navigationPath.isEmpty {
            navigationPath = [opportunity]
        }
        if arguments.contains("-review-map") {
            let mode = (arguments.contains("-review-map-detail") || arguments.contains("-review-virtual-detail")) ? "detail" : (selectedVenueID == nil ? "overview" : "selected")
            let mapped = venues.reduce(0) { $0 + $1.opportunities.count }
            FileHandle.standardOutput.write(Data(("GTA_MAP_REVIEW_READY \(mode) venues=\(venues.count) mapped=\(mapped) filtered=\(store.opportunities.count)\n").utf8))
        }
#endif
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
        "\(session.text("map")): \(mapProjection.snapshot.mappedCount) / \(store.opportunities.count) \(session.text("visible"))"
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
            store.clearActiveSavedSearch()
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
        await store.refreshIfStale(cache: persistenceContext)
    }

    private var persistenceContext: ModelContext? {
        storageAccess.allowsPersistentChanges ? modelContext : nil
    }
}

struct OpportunityRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity
    var showsDisclosure = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ActivityCategoryMark(category: opportunity.category)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(session.categoryName(for: opportunity))
                    .font(PortfolioTypography.caption.weight(.semibold))
                    .foregroundStyle(Brand.lake)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.title(for: opportunity))
                    .font(PortfolioTypography.headline.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(session.organization(for: opportunity)) · \(session.city(for: opportunity))")
                    .font(PortfolioTypography.subheadline)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let schedule = session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate) {
                    Label(schedule, systemImage: "calendar")
                        .font(PortfolioTypography.caption)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowLabels {
                    if let ageGuide = Self.ageGuideRange(for: opportunity) {
                        Text("\(session.text("ageGuide")): \(ageGuide)")
                    }
                    Label(opportunity.localizedCost(language: session.language), systemImage: "ticket")
                    if opportunity.status == "needs_review" || opportunity.isNewFind == true {
                        Label(session.text("newFind"), systemImage: "sparkles")
                    }
                    if let distanceKm = opportunity.distanceKm {
                        Label(session.text("distanceRadius").replacingOccurrences(of: "{km}", with: String(format: "%.1f", distanceKm)), systemImage: "mappin.and.ellipse")
                    }
                    if opportunity.volunteerHoursEligible {
                        Label(session.text("volunteerHours"), systemImage: "checkmark.seal")
                    }
                    if opportunity.coopEligible {
                        Label(session.text("coop"), systemImage: "briefcase")
                    }
                }
                .font(PortfolioTypography.caption)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(PortfolioTypography.caption.weight(.semibold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(session.text("openDetailsHint"))
    }

    static func ageGuideRange(for opportunity: Opportunity) -> String? {
        // A zero lower bound without an upper bound can be an unknown fallback,
        // not provider-confirmed eligibility for every age.
        guard opportunity.ageMin > 0 || opportunity.ageMax != nil else { return nil }
        return "\(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")"
    }

    private var accessibilityLabel: String {
        var parts = [
            "\(session.text("details")): \(session.title(for: opportunity))",
            "\(session.text("category")): \(session.categoryName(for: opportunity))",
            "\(session.text("hostOrgName")): \(session.organization(for: opportunity))",
            "\(session.text("city")) \(session.city(for: opportunity))"
        ]
        if let ageGuide = Self.ageGuideRange(for: opportunity) {
            parts.append("\(session.text("ageGuide")) \(ageGuide)")
        }
        parts.append(opportunity.localizedCost(language: session.language))
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
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var store: OpportunityStore
    @State private var saveFilterPresented = false
    @State private var savedFilterConfirmed = false
    @State private var previewing = false
    @State private var previewRevision = UUID()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: SessionStore
    @Binding var filters: OpportunityFilters
    let surface: BrowseSurface
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
                savedFiltersSection
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
                            .font(PortfolioTypography.headline.weight(.semibold))
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
            .tint(Brand.actionFill(for: colorScheme))
            .navigationTitle(session.text("filters"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                if savedFilterConfirmed {
                    Label(session.text("saved"), systemImage: "checkmark.circle")
                        .font(PortfolioTypography.callout)
                        .accessibilityIdentifier("filter-save-confirmed")
                }
                Button {
                    savedFilterConfirmed = false
                    saveFilterPresented = true
                } label: {
                    Label(session.text(store.activeSavedSearchID == nil ? "saveSearch" : "updateSearch"), systemImage: "bookmark.badge.plus")
                        .foregroundStyle(Brand.actionForeground(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!storageAccess.allowsPersistentChanges)
                .accessibilityIdentifier("save-named-search")
                }
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $saveFilterPresented) {
                SaveNamedSearchSheet(onSaved: { savedFilterConfirmed = true })
                    .environmentObject(session).environmentObject(store)
                    .environment(\.layoutDirection, session.language.layoutDirection)
                    .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack { resetButton; Spacer(minLength: 16); doneButton }
                    VStack(spacing: 8) { resetButton; doneButton }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: criteria) { _, _ in
                savedFilterConfirmed = false
                previewRevision = UUID()
            }
            .task(id: previewRevision) {
                previewing = true
                // Coalesce typing without delaying the preset selection itself.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await store.previewCurrentFilters()
                guard !Task.isCancelled else { return }
                previewing = false
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var criteria: NamedSearchCriteria {
        NamedSearchCriteria(query: store.query, mode: store.mode, filters: filters)
    }

    private var selectedPreset: NamedSavedSearch? {
        compatiblePresets.first { $0.id == store.activeSavedSearchID }
    }

    private var compatiblePresets: [NamedSavedSearch] {
        store.savedSearches.filter { surface.modes.contains($0.criteria.mode) }
    }

    private var savedFiltersSection: some View {
        Section(session.text("mySavedSearches")) {
            if compatiblePresets.isEmpty {
                Text(session.text("noCompatibleFilters"))
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button(session.text("newFilter"), action: startNewFilter)
                    ForEach(compatiblePresets) { preset in
                        Button {
                            savedFilterConfirmed = false
                            Task { await store.openNamedSearch(preset.id, acknowledge: false) }
                        } label: {
                            if store.activeSavedSearchID == preset.id {
                                Label(preset.name, systemImage: "checkmark")
                            } else { Text(preset.name) }
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedPreset?.name ?? session.text("newFilter"))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel(session.text("mySavedSearches"))
                .accessibilityValue(selectedPreset?.name ?? session.text("newFilter"))
                .accessibilityIdentifier("saved-filter-picker")
            }
            if let preset = selectedPreset, NamedSearchCriteria(query: preset.criteria.query, mode: preset.criteria.mode, filters: preset.criteria.filters) != criteria {
                Text(session.text("filterModified")).font(PortfolioTypography.callout).foregroundStyle(.secondary)
            }
            TextField(session.text("searchPlaceholder"), text: $store.query)
                .accessibilityIdentifier("filter-query")
            if previewing {
                ProgressView(session.text("updatingFilterResults"))
            } else {
                Text(session.text(store.opportunities.count == 1 ? "resultCountOne" : "resultCountMany")
                    .replacingOccurrences(of: "{count}", with: store.opportunities.count.formatted()))
                    .font(PortfolioTypography.headline)
                    .accessibilityIdentifier("filter-result-count")
            }
        }
    }

    private func startNewFilter() {
        store.clearActiveSavedSearch()
        store.query = ""
        store.mode = surface.defaultMode
        reset()
        savedFilterConfirmed = false
        previewRevision = UUID()
    }

    private var resetButton: some View {
        Button(action: startNewFilter) {
            Text(session.text("reset"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .accessibilityIdentifier("reset-filters")
    }

    private var doneButton: some View {
        Button(action: apply) {
            Text(session.text("done"))
                .foregroundStyle(Brand.actionForeground(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .accessibilityIdentifier("done-filters")
    }

}

private struct HuntRefreshButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isLoading: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading && !reduceMotion)
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

/// Projection runs only when filtered records are published, never on map gestures.
@MainActor
final class OpportunityMapPresentation: ObservableObject {
    @Published private(set) var snapshot = OpportunityMapSnapshot.empty
    @Published private(set) var revision = 0
    @Published private(set) var isPreparing = false
    private var generation = 0
    private var needsResume = false
    private var pending: Task<Void, Never>?
    private let project: @Sendable ([Opportunity]) async -> OpportunityMapSnapshot

    init(project: @escaping @Sendable ([Opportunity]) async -> OpportunityMapSnapshot = { records in
        let worker = Task.detached(priority: .userInitiated) {
            OpportunityMapProjection.snapshot(from: records)
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }) {
        self.project = project
    }

    @discardableResult
    func prepare(_ records: [Opportunity]) -> Task<Void, Never> {
        generation &+= 1
        needsResume = false
        let requestedGeneration = generation
        pending?.cancel()
        // Never display pins from a previous filter while its replacement is pending.
        snapshot = .empty
        isPreparing = true
        let project = project
        let task = Task { [weak self] in
            let result = await project(records)
            guard !Task.isCancelled, let self, self.generation == requestedGeneration else { return }
            self.snapshot = result
            self.revision = requestedGeneration
            self.isPreparing = false
        }
        pending = task
        return task
    }

    @discardableResult
    func resumeIfInterrupted(_ records: [Opportunity]) -> Task<Void, Never>? {
        guard needsResume else { return nil }
        return prepare(records)
    }

    func cancel() {
        needsResume = needsResume || isPreparing
        generation &+= 1
        pending?.cancel()
        pending = nil
        isPreparing = false
    }
}

/// MapKit owns zoom-dependent clustering and camera gestures. SwiftUI retains only
/// the selected real venue, so panning cannot rescan the opportunity catalogue.
struct ClusteredOpportunityMap: UIViewRepresentable {
    let snapshot: OpportunityMapSnapshot
    let revision: Int
    let resetRevision: Int
    @Binding var selectedVenueID: String?
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let language: AppLanguage
    let venueTitle: (OpportunityMapVenue) -> String
    let clusterTitle: (Int, Int) -> String
    let selectCoincidentVenues: ([String]) -> Void
    let clearCoincidentVenues: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.showsCompass = false
        map.register(OpportunityMapMarker.self, forAnnotationViewWithReuseIdentifier: "venue")
        map.register(OpportunityMapMarker.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.delegate = context.coordinator
        context.coordinator.addControls(to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(map)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredOpportunityMap
        private var displayedRevision: Int?
        private var displayedLanguage: AppLanguage?
        private var displayedResetRevision: Int?
        private var focusedVenueID: String?
        private var annotations: [String: OpportunityVenueAnnotation] = [:]
        private weak var map: MKMapView?
        private let pitchButton = UIButton(type: .system)
        private var applyingUpdate = false

        init(_ parent: ClusteredOpportunityMap) { self.parent = parent }

        func addControls(to map: MKMapView) {
            self.map = map
            var appearance = UIButton.Configuration.filled()
            appearance.baseBackgroundColor = .secondarySystemBackground
            appearance.baseForegroundColor = UIColor(Brand.lake)
            appearance.cornerStyle = .capsule
            pitchButton.configuration = appearance
            pitchButton.addTarget(self, action: #selector(togglePitch), for: .touchUpInside)
            let compass = MKCompassButton(mapView: map)
            compass.compassVisibility = .visible
            let scale = MKScaleView(mapView: map)
            scale.scaleVisibility = .adaptive
            for control in [pitchButton, compass, scale] {
                control.translatesAutoresizingMaskIntoConstraints = false
                map.addSubview(control)
            }
            NSLayoutConstraint.activate([
                pitchButton.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 8),
                pitchButton.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -8),
                pitchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                pitchButton.heightAnchor.constraint(equalToConstant: 44),
                compass.topAnchor.constraint(equalTo: pitchButton.bottomAnchor, constant: 8),
                compass.centerXAnchor.constraint(equalTo: pitchButton.centerXAnchor),
                compass.widthAnchor.constraint(equalToConstant: 44),
                compass.heightAnchor.constraint(equalToConstant: 44),
                scale.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 8),
                scale.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 8),
                scale.trailingAnchor.constraint(lessThanOrEqualTo: pitchButton.leadingAnchor, constant: -8)
            ])
            updatePitchLabel(map)
        }

        func update(_ map: MKMapView) {
            applyingUpdate = true
            defer { applyingUpdate = false }
            map.overrideUserInterfaceStyle = parent.colorScheme == .dark ? .dark : .light
            let newRecords = displayedRevision != parent.revision
            let newLabels = displayedLanguage != parent.language
            if newRecords || newLabels {
                map.removeAnnotations(Array(annotations.values))
                annotations = Dictionary(uniqueKeysWithValues: parent.snapshot.venues.map { venue in
                    let value = OpportunityVenueAnnotation(venue: venue, title: parent.venueTitle(venue))
                    return (venue.id, value)
                })
                map.addAnnotations(Array(annotations.values))
                displayedRevision = parent.revision
                displayedLanguage = parent.language
                focusedVenueID = nil
            }
            let cameraWasReset = newRecords || displayedResetRevision != parent.resetRevision
            if cameraWasReset {
                displayedResetRevision = parent.resetRevision
                if let viewport = parent.snapshot.viewport {
                    let camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: viewport.latitude, longitude: viewport.longitude),
                                             fromDistance: viewport.distance, pitch: viewport.pitch, heading: -12)
                    map.setCamera(camera, animated: false)
                }
            }
            if let id = parent.selectedVenueID, (cameraWasReset || id != focusedVenueID), let annotation = annotations[id] {
                focusedVenueID = id
                let camera = MKMapCamera(lookingAtCenter: annotation.coordinate, fromDistance: 2_400, pitch: 55, heading: -12)
                map.setCamera(camera, animated: !parent.reduceMotion)
                map.selectAnnotation(annotation, animated: !parent.reduceMotion)
            } else if parent.selectedVenueID == nil, focusedVenueID != nil {
                focusedVenueID = nil
                for annotation in map.selectedAnnotations { map.deselectAnnotation(annotation, animated: false) }
            }
            updatePitchLabel(map)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let isCluster = annotation is MKClusterAnnotation
            let identifier = isCluster ? MKMapViewDefaultClusterAnnotationViewReuseIdentifier : "venue"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier, for: annotation) as! OpportunityMapMarker
            view.annotation = annotation
            view.clusteringIdentifier = isCluster ? nil : "gta-physical-venues"
            view.collisionMode = .circle
            view.displayPriority = isCluster ? .required : .defaultHigh
            view.canShowCallout = false
            view.markerTintColor = UIColor(Brand.lake)
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .hidden
            view.glyphText = nil
            view.glyphImage = nil
            if let cluster = annotation as? MKClusterAnnotation {
                view.glyphText = "\(cluster.memberAnnotations.count)"
            } else if let venue = annotation as? OpportunityVenueAnnotation {
                view.glyphImage = UIImage(systemName: venue.eventCount > 1 ? "square.stack.3d.up.fill" : "mappin")
            }
            view.accessibilityLabel = annotation.title ?? nil
            view.accessibilityTraits.insert(.button)
            return view
        }

        func mapView(_ mapView: MKMapView, clusterAnnotationForMemberAnnotations members: [any MKAnnotation]) -> MKClusterAnnotation {
            let cluster = MKClusterAnnotation(memberAnnotations: members)
            let eventCount = members.compactMap { $0 as? OpportunityVenueAnnotation }.reduce(0) { $0 + $1.eventCount }
            cluster.title = parent.clusterTitle(members.count, eventCount)
            return cluster
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !applyingUpdate else { return }
            if let cluster = view.annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? OpportunityVenueAnnotation }
                guard let first = members.first else { return }
                let coincident = members.allSatisfy {
                    $0.coordinate.latitude == first.coordinate.latitude && $0.coordinate.longitude == first.coordinate.longitude
                }
                // Different source addresses at one coordinate remain separate venues.
                // They cannot be separated by zoom, so expose every real venue's rows.
                let revision = parent.revision
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.revision == revision else { return }
                    self.parent.selectedVenueID = nil
                    if coincident { self.parent.selectCoincidentVenues(members.map(\.venueID)) }
                    else { self.parent.clearCoincidentVenues() }
                }
                mapView.showAnnotations(cluster.memberAnnotations, animated: !parent.reduceMotion)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let venue = view.annotation as? OpportunityVenueAnnotation {
                let revision = parent.revision
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.revision == revision else { return }
                    self.parent.clearCoincidentVenues()
                    self.parent.selectedVenueID = venue.venueID
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { updatePitchLabel(mapView) }

        @objc private func togglePitch() {
            guard let map else { return }
            let camera = map.camera.copy() as! MKMapCamera
            camera.pitch = map.camera.pitch > 1 ? 0 : 55
            map.setCamera(camera, animated: !parent.reduceMotion)
            updatePitchLabel(map)
        }

        private func updatePitchLabel(_ map: MKMapView) {
            let target = map.camera.pitch > 1 ? "2D" : "3D"
            pitchButton.setTitle(target, for: .normal)
            pitchButton.accessibilityLabel = target
        }
    }
}

private final class OpportunityVenueAnnotation: NSObject, MKAnnotation {
    let venueID: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let eventCount: Int

    init(venue: OpportunityMapVenue, title: String) {
        venueID = venue.id
        coordinate = CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude)
        self.title = title
        eventCount = venue.opportunities.count
        super.init()
    }
}

private final class OpportunityMapMarker: MKMarkerAnnotationView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let target = bounds.insetBy(dx: -max(0, (44 - bounds.width) / 2), dy: -max(0, (44 - bounds.height) / 2))
        return target.contains(point)
    }
}

private struct SaveNamedSearchSheet: View {
    @Environment(\.appStorageAccess) private var storageAccess
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @State private var name = ""
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(session.text("filterName")) {
                    TextField(session.text("filterName"), text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("saved-search-name")
                }
                Section(session.text("filters")) {
                    Text(NamedSearchSummary.text(NamedSearchCriteria(query: store.query, mode: store.mode, filters: store.filters), session: session))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Button(session.text(store.activeSavedSearchID == nil ? "saveSearch" : "updateSearch")) {
                        save(updating: store.activeSavedSearchID)
                    }
                    .accessibilityIdentifier("confirm-save-search")
                    if store.activeSavedSearchID != nil {
                        Button(session.text("saveAsNew")) { save(updating: nil) }
                    }
                    if saving { ProgressView() }
                    if failed { Text(store.savedSearchError ?? session.text("savedSearchWriteError")).foregroundStyle(Brand.coral) }
                }
                .disabled(!storageAccess.allowsPersistentChanges || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || saving)
            }
            .scrollContentBackground(.hidden)
            .background(Brand.contentCanvas(for: colorScheme))
#if DEBUG
            .safeAreaInset(edge: .bottom) {
                if AppRuntime.isFrontendLayoutReview {
                    Text(session.text("layoutReviewBanner"))
                        .font(PortfolioTypography.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(8)
                        .foregroundStyle(Brand.navy).background(Brand.sun)
                }
            }
#endif
            .navigationTitle(session.text(store.activeSavedSearchID == nil ? "saveSearch" : "updateSearch"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(session.text("done"))
                }
            }
            .onAppear {
                if let id = store.activeSavedSearchID, let search = store.savedSearches.first(where: { $0.id == id }) { name = search.name }
#if DEBUG
                if AppRuntime.isFrontendLayoutReview {
                    if store.activeSavedSearchID == nil { name = "Sample: Weekend science" }
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "-runtime-ready-nonce"), arguments.indices.contains(index + 1), UUID(uuidString: arguments[index + 1]) != nil {
                        FileHandle.standardOutput.write(Data(("GTA_NAMED_SEARCH_SHEET_READY " + arguments[index + 1] + "\n").utf8))
                    }
                }
#endif
            }
        }
    }

    private func save(updating id: UUID?) {
        guard storageAccess.allowsPersistentChanges, !saving else { return }
        saving = true
        Task {
            let saved = await store.saveNamedSearch(name: name, updating: id)
            saving = false
            if saved { onSaved(); dismiss() } else { failed = true }
        }
    }
}
