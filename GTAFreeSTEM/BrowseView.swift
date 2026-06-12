import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var store: OpportunityStore

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        Picker("Pathway", selection: $store.mode) {
                            ForEach(SearchMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: store.mode) { _, _ in
                            Task { await store.refresh() }
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(store.opportunities) { opportunity in
                                NavigationLink(value: opportunity) {
                                    OpportunityRow(opportunity: opportunity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 112)
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $store.query, prompt: "Search free programs")
            .onSubmit(of: .search) {
                Task { await store.refresh() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
            .task {
                if store.opportunities.isEmpty {
                    await store.refresh()
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 118)
                .accessibilityHidden(true)
            Text("GTA FREE STEM")
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
            Text("Find free and accessible STEM opportunities across the GTA.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack {
                Label("\(store.activeCount) visible", systemImage: "sparkle.magnifyingglass")
                Spacer()
                if store.isLoading {
                    ProgressView()
                }
            }
            .font(.subheadline.weight(.semibold))
            Text("Loaded from \(store.dataSourceLabel)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var background: some View {
        LinearGradient(colors: [Brand.aqua.opacity(0.18), Brand.sun.opacity(0.14), Brand.mint.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct OpportunityRow: View {
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(opportunity.category)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Brand.sun.opacity(0.55), in: Capsule())
            Text(opportunity.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(opportunity.organization) · \(opportunity.city)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Label("Ages \(opportunity.ageMin)\(opportunity.ageMax.map { "–\($0)" } ?? "+")", systemImage: "person.2")
                if opportunity.volunteerHoursEligible {
                    Label("Hours", systemImage: "checkmark.seal")
                }
                if opportunity.coopEligible {
                    Label("SHSM", systemImage: "briefcase")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
