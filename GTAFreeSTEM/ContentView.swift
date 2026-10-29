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
        case .opportunities: "browse"
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
        .onAppear {
#if DEBUG
            // A smoke capture must observe the real shell after the unchanged
            // launch animation hands over, rather than photographing a timer.
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-runtime-ready-nonce"),
               args.indices.contains(index + 1), UUID(uuidString: args[index + 1]) != nil {
                FileHandle.standardOutput.write(Data(("GTA_RUNTIME_SHELL_READY " + args[index + 1] + "\n").utf8))
            }
#endif
        }
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
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @Binding var selectedTab: AppTab
    @State private var deletingSearch: NamedSavedSearch?
    @State private var deletionNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    masthead
                    Text(session.text("homePurpose"))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !store.savedSearches.isEmpty { savedSearchSection }
                    topicSection
                    Button(action: openResults) {
                        Label(session.text("browseAllActivities"), systemImage: "arrow.forward")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                    if store.savedSearches.isEmpty { savedSearchSection }
                    if let error = store.savedSearchError {
                        Text(error).font(.callout).foregroundStyle(Brand.coral)
                    }
                    if deletionNotice {
                        Label(session.text("searchDeleted"), systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(Brand.mutedText(for: colorScheme))
                            .accessibilityIdentifier("saved-search-deleted")
                    }
                    pathwayGrid
                    sourceFootnote
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Brand.contentCanvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(session.text("deleteSavedSearch"), isPresented: Binding(
                get: { deletingSearch != nil }, set: { if !$0 { deletingSearch = nil } }
            ), titleVisibility: .visible) {
                Button(session.text("deleteSavedSearch"), role: .destructive) {
                    if let search = deletingSearch { Task { deletionNotice = await store.deleteNamedSearch(search.id) } }
                    deletingSearch = nil
                }
            } message: { Text(deletingSearch?.name ?? "") }
        }
    }

    private var masthead: some View {
        HStack(spacing: 12) {
            BrandLogoImage(size: 48).accessibilityHidden(true)
            Text(Brand.compactName).font(.headline.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Spacer(minLength: 4)
            ThemeToolbarButton(showLabel: false)
        }
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.text("exploreTopics")).font(.title2.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .accessibilityAddTraits(.isHeader)
            if store.homeTopics.isEmpty {
                Text(session.text(store.isLoading ? "preparingOpportunities" : "noOpportunities"))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(store.homeTopics, id: \.self) { category in
                    Button {
                        store.beginNewSearch(category: category)
                        selectedTab = .opportunities
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            ActivityCategoryMark(category: category, size: 42)
                            HStack(alignment: .top, spacing: 6) {
                                Text(session.categoryName(category)).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.forward").font(.caption.weight(.bold)).accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(Brand.outline(for: colorScheme))
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(Brand.topicFill(category: category, scheme: colorScheme), in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .accessibilityIdentifier("home-topic-\(category)")
                }
            }
        }
    }

    private var savedSearchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.text("mySavedSearches")).font(.title2.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme)).accessibilityAddTraits(.isHeader)
            if store.savedSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bookmark").font(.title2).foregroundStyle(Brand.lake).accessibilityHidden(true)
                    Text(session.text("savedSearchEmpty")).font(.body)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Brand.topicFill(category: "Science & Engineering", scheme: colorScheme), in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(store.savedSearches) { search in
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            Task {
                                if await store.openNamedSearch(search.id, acknowledge: storageAccess.allowsPersistentChanges) {
                                    selectedTab = search.criteria.mode == .all ? .opportunities : .highSchool
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(search.name).font(.headline)
                                    Spacer(minLength: 4)
                                    Image(systemName: "arrow.forward").accessibilityHidden(true)
                                }
                                Text(NamedSearchSummary.text(search.criteria, session: session))
                                    .font(.subheadline).foregroundStyle(Brand.mutedText(for: colorScheme))
                                if let count = search.matchedCount {
                                    Text(OpportunityResultCountText.string(count, language: session.language)).font(.subheadline.weight(.semibold))
                                } else {
                                    Text(session.text("savedSearchPending")).font(.subheadline)
                                }
                                if !search.unreadIDs.isEmpty {
                                    Text(session.text("newSinceViewed").replacingOccurrences(of: "{count}", with: "\(search.unreadIDs.count)"))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.lake)
                                }
                                if let checked = search.checkedAt {
                                    Text("\(session.text("lastChecked")): \(checked.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(Brand.mutedText(for: colorScheme))
                                }
                            }
                            .foregroundStyle(Brand.outline(for: colorScheme))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SpringPressButtonStyle())
                        .accessibilityIdentifier("open-saved-search-\(search.id)")
                        HStack {
                            if !search.unreadIDs.isEmpty {
                                Button(session.text("markRead")) { Task { await store.markNamedSearchRead(search.id) } }
                                    .frame(minHeight: 44)
                            }
                            Spacer()
                            Button(session.text("deleteSavedSearch"), role: .destructive) { deletingSearch = search }
                                .frame(minHeight: 44)
                        }
                        .font(.subheadline).disabled(!storageAccess.allowsPersistentChanges)
                        Divider()
                    }
                }
            }
        }
    }

    private var pathwayGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.availableHomePathwayModes.contains(.volunteer) {
                pathwayRow(session.text("volunteerHours"), icon: "hands.sparkles") { openPathway(.volunteer) }
            }
            if store.availableHomePathwayModes.contains(.coop) {
                pathwayRow(session.text("coop"), icon: "briefcase") { openPathway(.coop) }
            }
            if store.availableHomePathwayModes.contains(.mentorship) {
                pathwayRow(session.text("mentorship"), icon: "person.2") { openPathway(.mentorship) }
            }
            pathwayRow(session.text("feedback"), icon: "bubble.left") { selectedTab = .support }
        }
    }

    private func pathwayRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .foregroundStyle(Brand.lake).buttonStyle(SpringPressButtonStyle())
    }

    private var sourceFootnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.text("homeCatalogNote"))
            if let lastUpdated = store.lastUpdated {
                Text("\(session.text("date")): \(session.formattedDate(lastUpdated))")
                    .accessibilityIdentifier("feed-last-updated")
            }
        }
        .font(.footnote).foregroundStyle(Brand.mutedText(for: colorScheme))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openResults() {
        store.beginNewSearch()
        selectedTab = .opportunities
    }

    private func openPathway(_ mode: SearchMode) {
        store.beginNewSearch()
        store.mode = mode
        selectedTab = .highSchool
    }
}

@MainActor
enum NamedSearchSummary {
    static func text(_ criteria: NamedSearchCriteria, session: SessionStore) -> String {
        var parts: [String] = []
        if !criteria.query.isEmpty { parts.append(criteria.query) }
        if !criteria.filters.city.isEmpty { parts.append(criteria.filters.city) }
        if criteria.filters.category != "All" { parts.append(session.categoryName(criteria.filters.category)) }
        if !criteria.filters.age.isEmpty { parts.append("\(session.text("age")): \(criteria.filters.age)") }
        if criteria.mode != .all { parts.append(session.text(criteria.mode.textKey)) }
        if criteria.filters.region != "All" { parts.append(criteria.filters.region) }
        if criteria.filters.volunteerHours { parts.append(session.text("volunteerHours")) }
        if criteria.filters.coop { parts.append(session.text("coop")) }
        if criteria.filters.mentorship { parts.append(session.text("mentorship")) }
        if criteria.filters.scholarships { parts.append(session.categoryName("Scholarships")) }
        if criteria.filters.hasLocation { parts.append(session.text("distanceRadius").replacingOccurrences(of: "{km}", with: "\(Int(criteria.filters.distanceKm))")) }
        return parts.isEmpty ? session.text("allCategories") : parts.joined(separator: " · ")
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
