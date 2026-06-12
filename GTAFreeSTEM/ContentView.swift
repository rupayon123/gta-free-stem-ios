import SwiftUI

enum AppTab: Hashable {
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
        return .home
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @State private var selectedTab: AppTab = AppTab.launchDefault

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label(session.text("home"), systemImage: "house.fill") }
                .tag(AppTab.home)

            BrowseView(surface: .opportunities)
                .tabItem { Label(session.text("navOpportunities"), systemImage: "magnifyingglass") }
                .tag(AppTab.opportunities)

            BrowseView(surface: .highSchool)
                .tabItem { Label(session.text("highSchool"), systemImage: "graduationcap.fill") }
                .tag(AppTab.highSchool)

            SubmitView()
                .tabItem { Label(session.text("support"), systemImage: "plus.message.fill") }
                .tag(AppTab.support)

            SettingsView()
                .tabItem { Label(session.text("account"), systemImage: "person.crop.circle.fill") }
                .tag(AppTab.account)
        }
        .tint(Brand.coral)
        .onChange(of: selectedTab) { _, newTab in
            configureStore(for: newTab)
        }
        .onOpenURL { url in
            guard let tab = AppTab(url: url) else { return }
            selectedTab = tab
            configureStore(for: tab)
        }
    }

    private func configureStore(for tab: AppTab) {
        switch tab {
        case .opportunities:
            store.mode = .all
            Task { await store.refresh(cache: modelContext) }
        case .highSchool:
            store.mode = .highSchool
            Task { await store.refresh(cache: modelContext) }
        case .home, .support, .account:
            break
        }
    }
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: OpportunityStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        heroCard
                        searchEntryCard
                        statusCard
                        pathwayGrid
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if store.opportunities.isEmpty {
                    await store.refresh(cache: modelContext)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            BrandLogoImage(size: 156)
                .accessibilityHidden(true)

            Text(session.text("brand"))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)

            Text(session.text("mission"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .multilineTextAlignment(.center)

            StickerBadge(text: session.text("freeOnly"), color: Brand.sun, systemImage: "heart.fill")
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 16, cornerRadius: 34)
    }

    private var searchEntryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("search"), systemImage: "sparkle.magnifyingglass")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Brand.coral)
                TextField(session.text("searchPlaceholder"), text: $store.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        store.mode = .all
                        selectedTab = .opportunities
                        Task { await store.refresh(cache: modelContext) }
                    }
            }
            .storyField()

            HStack(spacing: 10) {
                Button {
                    store.mode = .all
                    selectedTab = .opportunities
                    Task { await store.refresh(cache: modelContext, prioritized: true) }
                } label: {
                    Label(session.text("search"), systemImage: "magnifyingglass")
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .primary))

                Button {
                    store.mode = .highSchool
                    selectedTab = .highSchool
                    Task { await store.refresh(cache: modelContext, prioritized: true) }
                } label: {
                    Label(session.text("highSchool"), systemImage: "graduationcap.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: .secondary))
            }
        }
        .cardSurface(padding: 16, cornerRadius: 30)
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Brand.coral)
                .symbolEffect(.pulse, value: store.isLoading)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(store.activeCount) \(session.text("visible"))")
                    .font(.title3.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                Text("\(session.text("loadedFrom")) \(localizedDataSource)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }

            Spacer()

            Button {
                Task { await store.refresh(cache: modelContext, prioritized: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline.weight(.black))
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
            .accessibilityLabel(session.text("refreshResearch"))
        }
        .cardSurface(padding: 16, cornerRadius: 28)
    }

    private var pathwayGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            HomeActionTile(title: session.text("volunteerHours"), icon: "checkmark.seal.fill", color: Brand.moss) {
                store.mode = .volunteer
                selectedTab = .highSchool
                Task { await store.refresh(cache: modelContext, prioritized: true) }
            }
            HomeActionTile(title: session.text("coop"), icon: "briefcase.fill", color: Brand.lavender) {
                store.mode = .coop
                selectedTab = .highSchool
                Task { await store.refresh(cache: modelContext, prioritized: true) }
            }
            HomeActionTile(title: session.text("mentorship"), icon: "person.2.wave.2.fill", color: Brand.sky) {
                store.mode = .mentorship
                selectedTab = .highSchool
                Task { await store.refresh(cache: modelContext, prioritized: true) }
            }
            HomeActionTile(title: session.text("feedback"), icon: "bubble.left.and.bubble.right.fill", color: Brand.coral) {
                selectedTab = .support
            }
        }
    }

    private var localizedDataSource: String {
        store.dataSourceLabel == "Preview database" ? session.text("previewDatabase") : session.text("railsAPI")
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
                    .font(.title2.weight(.black))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 46, height: 46)
                    .background(color, in: Circle())
                    .overlay {
                        Circle().stroke(Brand.outline(for: colorScheme), lineWidth: 2)
                    }
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .cardSurface(padding: 14, cornerRadius: 26)
    }
}
