import Accessibility
import SwiftData
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home
    case opportunities
    case highSchool
    case support
    case account

    init?(url: URL) {
        let target = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .compactMap { $0 }
            .first { !$0.isEmpty }?
            .lowercased()

        switch target {
        case "home":
            self = .home
        case "opportunities", "hunt", "search":
            self = .opportunities
        case "high-school", "highschool", "school":
            self = .highSchool
        case "support", "feedback", "submit":
            self = .support
        case "account", "settings":
            self = .account
        default:
            return nil
        }
    }

    static var launchDefault: AppTab {
        let arguments = ProcessInfo.processInfo.arguments.map { $0.lowercased() }
        if arguments.contains("-start-opportunities") {
            return .opportunities
        }
        if arguments.contains("-start-high-school") {
            return .highSchool
        }
        if arguments.contains("-start-support") {
            return .support
        }
        if arguments.contains("-start-account") {
            return .account
        }
        return .home
    }

    var titleKey: String {
        switch self {
        case .home: "home"
        case .opportunities: "navOpportunities"
        case .highSchool: "highSchool"
        case .support: "support"
        case .account: "account"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .opportunities: "magnifyingglass"
        case .highSchool: "graduationcap.fill"
        case .support: "plus.message.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

enum AppLaunchConfiguration {
    static let screenshotQueryEnvironmentKey = "GTA_FREE_STEM_SCREENSHOT_QUERY"
    static let screenshotModeEnvironmentKey = "GTA_FREE_STEM_SCREENSHOT_MODE"
    static let screenshotReadyNonceEnvironmentKey = "GTA_FREE_STEM_SCREENSHOT_READY_NONCE"
    static let screenshotReadyMarkerFilename = "gta-free-stem-screenshot-ready"
    static let screenshotModeArgument = "-screenshot-mode"
    static let screenshotReadyNonceArgument = "-screenshot-ready-nonce"

    static func screenshotQuery(arguments: [String], environment: [String: String] = [:]) -> String? {
        if let optionIndex = arguments.firstIndex(where: { $0.caseInsensitiveCompare("-screenshot-query") == .orderedSame }),
           arguments.indices.contains(optionIndex + 1),
           let query = normalizedScreenshotQuery(arguments[optionIndex + 1]) {
            return query
        }

        return normalizedScreenshotQuery(environment[screenshotQueryEnvironmentKey])
    }

    static var screenshotQuery: String? {
        screenshotQuery(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }

    static func isScreenshotCapture(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> Bool {
        if arguments.contains(where: { $0.caseInsensitiveCompare(screenshotModeArgument) == .orderedSame }) {
            return true
        }
        guard let value = environment[screenshotModeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return ["1", "true", "yes"].contains(value)
    }

    static var isScreenshotCapture: Bool {
        isScreenshotCapture(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func markScreenshotReady(
        _ isReady: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        guard isReady,
              let nonce = screenshotReadyNonce(arguments: arguments, environment: environment),
              let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return
        }

#if DEBUG
        if AppRuntime.isFrontendLayoutReview {
            FileHandle.standardOutput.write(Data(("GTA_LAYOUT_REVIEW_READY " + nonce + "\n").utf8))
        }
#endif
        let marker = cachesDirectory.appendingPathComponent(screenshotReadyMarkerFilename, isDirectory: false)
        try? Data(nonce.utf8).write(to: marker, options: .atomic)
    }

    private static func normalizedScreenshotQuery(_ value: String?) -> String? {
        guard let value else { return nil }
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    private static func normalizedScreenshotNonce(_ value: String?) -> String? {
        guard let value else { return nil }
        let nonce = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nonce.isEmpty, nonce.count <= 200 else { return nil }
        return nonce
    }

    private static func screenshotReadyNonce(
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        if let optionIndex = arguments.firstIndex(where: {
            $0.caseInsensitiveCompare(screenshotReadyNonceArgument) == .orderedSame
        }), arguments.indices.contains(optionIndex + 1),
           let nonce = normalizedScreenshotNonce(arguments[optionIndex + 1]) {
            return nonce
        }
        return normalizedScreenshotNonce(environment[screenshotReadyNonceEnvironmentKey])
    }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appStorageAccess) private var storageAccess
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @State private var selectedTab: AppTab = AppTab.launchDefault

    var body: some View {
        Group {
            if usesSidebarNavigation {
                sidebarNavigation
            } else {
                tabNavigation
            }
        }
        .tint(Brand.lake)
        .accessibilityIdentifier("app-root")
        .safeAreaInset(edge: .top, spacing: 0) {
            if !storageAccess.allowsPersistentChanges {
                StorageRecoveryBanner()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: selectedTab)
        .onChange(of: accessibilityStatus) { oldStatus, newStatus in
            guard voiceOverEnabled,
                  oldStatus != newStatus,
                  let message = accessibilityAnnouncement(for: newStatus)
            else { return }

            // Announcements describe asynchronous updates without moving the
            // VoiceOver cursor away from the control the person is using.
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: selectedTab) { _, newTab in
            configureStore(for: newTab)
        }
        .onOpenURL { url in
            guard let tab = AppTab(url: url) else { return }
            selectedTab = tab
            configureStore(for: tab)
        }
        .task {
            guard !AppRuntime.isRunningTests else { return }
            applyScreenshotConfigurationIfNeeded()
            if AppLaunchConfiguration.isScreenshotCapture {
                // App Store capture uses the exact release UI with app-owned,
                // clearly labelled sample content. Static marketing images
                // cannot carry third-party providers' required clickable links.
                // Browse destinations own their readiness signal because their
                // surface mode and query must be applied before capture.
                if selectedTab != .opportunities && selectedTab != .highSchool {
                    let isReady = await store.prepareScreenshotSnapshot()
                    AppLaunchConfiguration.markScreenshotReady(isReady)
                }
            } else {
                await store.bootstrap(cache: persistenceContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  !AppRuntime.isRunningTests,
                  !AppLaunchConfiguration.isScreenshotCapture
            else { return }
            Task { await store.refreshIfStale(cache: persistenceContext) }
        }
    }

    private var tabNavigation: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem { Label(session.text(tab.titleKey), systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
    }

    private var sidebarNavigation: some View {
        NavigationSplitView {
            List {
                Section(Brand.compactName) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(session.text(tab.titleKey), systemImage: tab.symbolName)
                                .font(.body.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(
                                    selectedTab == tab
                                        ? Brand.actionFill(for: session.colorScheme ?? .light)
                                        : .primary
                                )
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedTab == tab
                                ? Brand.selectionFill(for: session.colorScheme ?? .light)
                                : Color.clear
                        )
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Brand.canvas(for: session.colorScheme ?? .light))
            .navigationTitle(Brand.compactName)
        } detail: {
            tabContent(for: selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(selectedTab: $selectedTab)
        case .opportunities:
            BrowseView(surface: .opportunities)
        case .highSchool:
            BrowseView(surface: .highSchool)
        case .support:
            SubmitView()
        case .account:
            if AppRuntime.isFrontendSavedLayoutReview {
                SavedView()
            } else {
                SettingsView()
            }
        }
    }

    private var usesSidebarNavigation: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var accessibilityStatus: OpportunityAccessibilityStatus {
        guard selectedTab == .home || selectedTab == .opportunities || selectedTab == .highSchool else {
            return .inactive
        }
        if store.isLoading {
            return .loading
        }
        if let errorMessage = store.errorMessage {
            return .error(errorMessage)
        }
        if store.huntPhase == .offline {
            return .offline(resultCount: store.opportunities.count)
        }
        return .results(count: store.opportunities.count)
    }

    private func accessibilityAnnouncement(for status: OpportunityAccessibilityStatus) -> String? {
        switch status {
        case .inactive:
            nil
        case .loading:
            session.text("huntingNow")
        case let .error(message):
            message
        case let .offline(resultCount):
            "\(session.text("offlinePreview")). \(localizedResultCount(resultCount))"
        case let .results(count):
            localizedResultCount(count)
        }
    }

    private var persistenceContext: ModelContext? {
        storageAccess.allowsPersistentChanges ? modelContext : nil
    }

    private func localizedResultCount(_ count: Int) -> String {
        OpportunityResultCountText.string(count, language: session.language)
    }

    private func configureStore(for tab: AppTab) {
        store.mode = AppNavigationModePolicy.mode(for: tab, currentMode: store.mode)
        guard !AppLaunchConfiguration.isScreenshotCapture else { return }
        switch tab {
        case .opportunities:
            Task { await store.refreshIfStale(cache: persistenceContext) }
        case .highSchool:
            Task { await store.refreshIfStale(cache: persistenceContext) }
        case .home, .support, .account:
            break
        }
    }

    private func applyScreenshotConfigurationIfNeeded() {
        guard let screenshotQuery = AppLaunchConfiguration.screenshotQuery else { return }

        store.query = screenshotQuery
        store.mode = selectedTab == .highSchool ? .highSchool : .all
    }
}

private struct StorageRecoveryBanner: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.text("localStorageUnavailableTitle"))
                    .font(.footnote.weight(.bold))
                Text(session.text("localStorageUnavailableMessage"))
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(Brand.coral)
        }
        // This banner deliberately keeps a fixed paper surface in both schemes;
        // fixed dark ink preserves critical recovery-copy contrast in dark mode.
        .foregroundStyle(Brand.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.standard)
        .padding(.vertical, AppSpacing.small)
        .background(Brand.cream)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Brand.coral)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storage-read-only-notice")
    }
}

enum AppNavigationModePolicy {
    static func mode(for tab: AppTab, currentMode: SearchMode) -> SearchMode {
        switch tab {
        case .opportunities:
            return .all
        case .highSchool:
            return BrowseSurface.highSchool.modes.contains(currentMode) ? currentMode : .highSchool
        case .home, .support, .account:
            return currentMode
        }
    }
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @Binding var selectedTab: AppTab



    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        masthead
                        searchSection
                        interestStrip
                        activitySection
                        pathwayGrid
                        sourceFootnote
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.standard)
                    .padding(.top, AppSpacing.small)
                    .padding(.bottom, 88)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
        }
    }

    private var homeAccent: Color { colorScheme == .dark ? Brand.ice : Brand.lake }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 13) {
            Rectangle()
                .fill(Brand.sun)
                .frame(width: 52, height: 5)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 12) {
                BrandLogoImage(size: 70)
                    .accessibilityHidden(true)
                Text(Brand.compactName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ThemeToolbarButton(showLabel: false)
            }

            Text(session.text("mission"))
                .font(.body)
                .foregroundStyle(Brand.outline(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.text("search"))
                .font(.title3.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(homeAccent)
                    .accessibilityHidden(true)
                TextField(session.text("searchPlaceholder"), text: $store.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(openResults)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Brand.cardFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Brand.outline(for: colorScheme).opacity(0.38), lineWidth: 1)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { cityMenu; ageMenu }
            } else {
                HStack(spacing: 10) { cityMenu; ageMenu }
            }
            categoryMenu

            Button(action: openResults) {
                HStack {
                    Text(session.text("browse"))
                    Spacer()
                    Image(systemName: "arrow.forward").accessibilityHidden(true)
                }
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .primary))

            Button {
                openPathway(.highSchool)
            } label: {
                Label(session.text("highSchool"), systemImage: "graduationcap.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(homeAccent)
        }
    }

    private var cityMenu: some View {
        Menu {
            Button(session.text("allCities")) { selectCity("") }
            ForEach(store.availableFilterCities, id: \.self) { city in
                Button(city) { selectCity(city) }
            }
        } label: {
            filterLabel(title: session.text("city"),
                        value: store.filters.city.isEmpty ? session.text("allCities") : store.filters.city,
                        icon: "mappin.and.ellipse")
        }
        .accessibilityLabel("\(session.text("city")): \(store.filters.city.isEmpty ? session.text("allCities") : store.filters.city)")
    }

    private var interestStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                interestButton(category: "Science & Engineering", icon: "atom", color: Brand.sky)
                interestButton(category: "Coding & Robotics", icon: "curlybraces", color: Brand.sun)
                interestButton(category: "Makerspace & Fabrication", icon: "paintpalette.fill", color: Brand.coral)
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button(session.text("allCategories")) { selectCategory("All") }
            ForEach(store.availableFilterCategories, id: \.self) { category in
                Button(session.categoryName(category)) { selectCategory(category) }
            }
        } label: {
            filterLabel(title: session.text("category"),
                        value: store.filters.category == "All" ? session.text("allCategories") : session.categoryName(store.filters.category),
                        icon: "square.grid.2x2")
        }
        .accessibilityLabel("\(session.text("category")): \(store.filters.category == "All" ? session.text("allCategories") : session.categoryName(store.filters.category))")
        .accessibilityIdentifier("home-category-filter")
    }

    private func interestButton(category: String, icon: String, color: Color) -> some View {
        Button {
            store.filters.category = category
            openResults()
        } label: {
            HStack(spacing: 7) {
                Label(session.categoryName(category), systemImage: icon)
                if store.filters.category == category {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                }
            }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(color.opacity(colorScheme == .dark ? 0.28 : 0.22), in: Capsule())
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityAddTraits(store.filters.category == category ? .isSelected : [])
    }

    private var ageMenu: some View {
        Menu {
            Button(session.text("any")) { selectAge("") }
            ForEach(0...17, id: \.self) { age in
                Button("\(age)") { selectAge("\(age)") }
            }
            Button { selectAge("18+") } label: {
                Text(verbatim: "18+")
            }
        } label: {
            filterLabel(title: session.text("age"),
                        value: store.filters.age.isEmpty ? session.text("any") : store.filters.age,
                        icon: "person.2")
        }
        .accessibilityLabel("\(session.text("age")): \(store.filters.age.isEmpty ? session.text("any") : store.filters.age)")
    }

    private func filterLabel(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(homeAccent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Brand.outline(for: colorScheme))
        .padding(.horizontal, 11)
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.cardFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Brand.outline(for: colorScheme).opacity(0.28), lineWidth: 1)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.text("navOpportunities"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                Spacer()
                if store.activeCount > 0 {
                    Text(OpportunityResultCountText.string(store.activeCount, language: session.language))
                        .font(.caption)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }
            }
            .padding(.bottom, 8)

            if store.opportunities.isEmpty {
                if store.isLoading {
                    ProgressView(session.text("preparingOpportunities"))
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                } else {
                    Text(store.errorMessage ?? session.text("noOpportunities"))
                        .font(.subheadline)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                }
            } else {
                ForEach(Array(store.opportunities.prefix(2))) { opportunity in
                    NavigationLink(value: opportunity) {
                        activityRow(opportunity)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Brand.outline(for: colorScheme).opacity(0.16))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func activityRow(_ opportunity: Opportunity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categorySymbol(opportunity.category))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.navy)
                .frame(width: 40, height: 40)
                .background(Brand.sun.opacity(0.66), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(opportunity.localizedTitle(language: session.language))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(opportunity.localizedOrganization(language: session.language)) · \(opportunity.city)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let schedule = session.formattedSchedule(start: opportunity.startDate, end: opportunity.endDate) {
                    Label(schedule, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(homeAccent)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint(session.text("openDetailsHint"))
    }

    private func categorySymbol(_ category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("coding") || lower.contains("robot") || lower.contains("digital") { return "curlybraces" }
        if lower.contains("nature") || lower.contains("environment") { return "leaf.fill" }
        if lower.contains("art") || lower.contains("maker") { return "paintpalette.fill" }
        if lower.contains("science") || lower.contains("stem") { return "atom" }
        return "book.closed.fill"
    }

    private var pathwayGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.text("exploreMore"))
                .font(.headline.weight(.bold))
                .padding(.bottom, 4)
            if store.availableHomePathwayModes.contains(.volunteer) {
                pathwayRow(session.text("volunteerHours"), icon: "checkmark.seal.fill") {
                    openPathway(.volunteer)
                }
            }
            if store.availableHomePathwayModes.contains(.coop) {
                pathwayRow(session.text("coop"), icon: "briefcase.fill") {
                    openPathway(.coop)
                }
            }
            if store.availableHomePathwayModes.contains(.mentorship) {
                pathwayRow(session.text("mentorship"), icon: "person.2.fill") {
                    openPathway(.mentorship)
                }
            }
            pathwayRow(session.text("feedback"), icon: "bubble.left.and.bubble.right.fill") {
                selectedTab = .support
            }
        }
    }

    private func pathwayRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(homeAccent).frame(width: 26)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var sourceFootnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Brand.moss)
                .accessibilityHidden(true)
            Text(session.text("freeShort"))
            if let lastUpdated = store.lastUpdated {
                Text(verbatim: "· \(session.text("lastVerified")) \(session.formattedDate(lastUpdated))")
            }
        }
        .font(.caption)
        .foregroundStyle(Brand.mutedText(for: colorScheme))
        .accessibilityIdentifier("feed-last-updated")
    }

    private func selectCity(_ city: String) {
        store.useCity(city)
        store.mode = .all
        Task { await store.refresh(cache: persistenceContext) }
    }

    private func selectAge(_ age: String) {
        store.filters.age = age
        store.mode = .all
        Task { await store.refresh(cache: persistenceContext) }
    }

    private func selectCategory(_ category: String) {
        store.filters.category = category
        store.mode = .all
        Task { await store.refresh(cache: persistenceContext) }
    }

    private func openResults() {
        store.mode = .all
        selectedTab = .opportunities
        Task { await store.refresh(cache: persistenceContext) }
    }

    private func openPathway(_ mode: SearchMode) {
        store.mode = mode
        selectedTab = .highSchool
        Task { await store.refresh(cache: persistenceContext) }
    }

    private var persistenceContext: ModelContext? {
        storageAccess.allowsPersistentChanges ? modelContext : nil
    }
}

private enum OpportunityAccessibilityStatus: Equatable {
    case inactive
    case loading
    case error(String)
    case offline(resultCount: Int)
    case results(count: Int)
}

enum OpportunityResultCountText {
    static func string(_ count: Int, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language.localeIdentifier)
        let formattedCount = formatter.string(from: NSNumber(value: count)) ?? String(count)
        let key = count == 1 ? "resultCountOne" : "resultCountMany"
        return AppText.shared.string(key, language: language)
            .replacingOccurrences(of: "{count}", with: formattedCount)
    }
}
