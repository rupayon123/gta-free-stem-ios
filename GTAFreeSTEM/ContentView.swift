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
            SettingsView()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
                    VStack(spacing: AppSpacing.standard) {
                        heroCard
                        searchEntryCard
                        statusCard
                        pathwayGrid
                    }
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.standard)
                    .padding(.top, AppSpacing.small)
                    .padding(.bottom, 88)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                BrandLogoImage(size: 64)
                    .accessibilityHidden(true)
                Text(session.text("brand"))
                    .font(.title.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ThemeToolbarButton(showLabel: false)
            }

            Text(session.text("mission"))
                .font(.body)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            StickerBadge(text: session.text("freeOnly"), color: Brand.sun, systemImage: "heart.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(Brand.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: AppRadius.feature))
    }

    private var searchEntryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            StorySectionTitle(text: session.text("search"), systemImage: "sparkle.magnifyingglass")

            DiscoveryLoupeScene(progress: min(CGFloat(store.query.count) / 16, 1))
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: store.query)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.lake)
                TextField(session.text("searchPlaceholder"), text: $store.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        store.mode = .all
                        selectedTab = .opportunities
                        Task { await store.refresh(cache: persistenceContext) }
                    }
            }
            .storyField()

            searchActions
        }
        .cardSurface()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(store.isLoading ? Brand.lake : Brand.moss)
                    .symbolEffect(.pulse, options: .repeating, isActive: store.isLoading && !reduceMotion)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(store.activeCount) \(session.text("visible"))")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                    Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                        .font(.subheadline)
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                    if let lastUpdated = store.lastUpdated {
                        Label("\(session.text("date")): \(session.formattedDate(lastUpdated))", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.mutedText(for: colorScheme))
                            .accessibilityIdentifier("feed-last-updated")
                    }
                }

                Spacer()

                Button {
                    Task { await store.refresh(cache: persistenceContext) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline.weight(.semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(StoryButtonStyle(kind: .quiet))
                .accessibilityLabel(session.text("refreshResearch"))
            }
            .cardSurface()

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Brand.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pathwayGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            HomeActionTile(title: session.text("browse"), icon: "rectangle.grid.2x2.fill", color: Brand.lake) {
                store.mode = .all
                selectedTab = .opportunities
                Task { await store.refresh(cache: persistenceContext) }
            }

            if store.availableHomePathwayModes.contains(.volunteer) {
                HomeActionTile(title: session.text("volunteerHours"), icon: "checkmark.seal.fill", color: Brand.moss) {
                    store.mode = .volunteer
                    selectedTab = .highSchool
                    Task { await store.refresh(cache: persistenceContext) }
                }
            }

            if store.availableHomePathwayModes.contains(.coop) {
                HomeActionTile(title: session.text("coop"), icon: "briefcase.fill", color: Brand.lavender) {
                    store.mode = .coop
                    selectedTab = .highSchool
                    Task { await store.refresh(cache: persistenceContext) }
                }
            }

            if store.availableHomePathwayModes.contains(.mentorship) {
                HomeActionTile(title: session.text("mentorship"), icon: "person.2.wave.2.fill", color: Brand.sky) {
                    store.mode = .mentorship
                    selectedTab = .highSchool
                    Task { await store.refresh(cache: persistenceContext) }
                }
            }

            HomeActionTile(title: session.text("feedback"), icon: "bubble.left.and.bubble.right.fill", color: Brand.coral) {
                selectedTab = .support
            }
        }
    }

    private var searchActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                allOpportunitiesButton
                highSchoolButton
            }

            VStack(spacing: 10) {
                allOpportunitiesButton
                highSchoolButton
            }
        }
    }

    private var allOpportunitiesButton: some View {
        Button {
            store.mode = .all
            selectedTab = .opportunities
            Task { await store.refresh(cache: persistenceContext) }
        } label: {
            Label(session.text("search"), systemImage: "magnifyingglass")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .primary))
    }

    private var highSchoolButton: some View {
        Button {
            store.mode = .highSchool
            selectedTab = .highSchool
            Task { await store.refresh(cache: persistenceContext) }
        } label: {
            Label(session.text("highSchool"), systemImage: "graduationcap.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .secondary))
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

private struct HomeActionTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? Brand.ice : Brand.navy)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(colorScheme == .dark ? 0.28 : 0.18), in: Circle())
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .cardSurface(padding: 14, cornerRadius: AppRadius.card)
        }
        .buttonStyle(SpringPressButtonStyle())
    }
}
