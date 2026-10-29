import SwiftData
import SwiftUI

struct SavedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appStorageAccess) private var storageAccess
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \SavedOpportunityRecord.savedAt, order: .reverse) private var savedRecords: [SavedOpportunityRecord]
    @State private var saveErrorMessage: String?

    private var savedEntries: [SavedOpportunityEntry] {
        savedRecords.compactMap { record in
            record.opportunity.map { SavedOpportunityEntry(record: record, opportunity: $0) }
        }
    }

    private var currentEntries: [SavedOpportunityEntry] {
        savedEntries.filter { !LocalOpportunitySnapshot.isArchived($0.opportunity) }
    }

    private var archivedEntries: [SavedOpportunityEntry] {
        savedEntries.filter { LocalOpportunitySnapshot.isArchived($0.opportunity) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                if !storageAccess.allowsPersistentChanges {
                    storageRecoveryState
                } else if savedEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        if !currentEntries.isEmpty {
                            Section {
                                ForEach(currentEntries) { entry in
                                    SavedOpportunityListItem(opportunity: entry.opportunity)
                                }
                                .onDelete { remove(at: $0, from: currentEntries) }
                            } header: {
                                Text(session.text("saved"))
                            }
                        }

                        if !archivedEntries.isEmpty {
                            Section {
                                ForEach(archivedEntries) { entry in
                                    SavedOpportunityListItem(opportunity: entry.opportunity)
                                }
                                .onDelete { remove(at: $0, from: archivedEntries) }
                            } header: {
                                Text(session.text("archive"))
                            } footer: {
                                Text(session.text("savedArchiveNote"))
                            }
                        }

                        if let saveErrorMessage {
                            Section {
                                Text(saveErrorMessage)
                                    .foregroundStyle(Brand.coral)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .tint(Brand.actionFill(for: colorScheme))
                }
            }
            .task {
#if DEBUG
                if AppRuntime.isFrontendSavedLayoutReview {
                    // A saved-screen marker follows a real query and a rendered turn,
                    // rather than merely acknowledging fixture preparation.
                    guard savedRecords.count == 3 else { return }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let args = ProcessInfo.processInfo.arguments
                    if let index = args.firstIndex(of: "-screenshot-ready-nonce"), args.indices.contains(index + 1) {
                        FileHandle.standardOutput.write(Data(("GTA_SAVED_REVIEW_READY " + args[index + 1] + "\n").utf8))
                    }
                }
#endif
            }
            .navigationTitle(session.text("saved"))
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.standard) {
            Image(systemName: "bookmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Brand.lake)
                .frame(width: 72, height: 72)
                .background(Brand.selectionFill(for: colorScheme), in: Circle())

            Text(session.text("savedEmpty"))
                .font(PortfolioTypography.title2.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .multilineTextAlignment(.center)

            Text(session.text("savedArchiveNote"))
                .font(PortfolioTypography.body)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.large)
        .frame(maxWidth: 560)
        .padding(AppSpacing.standard)
    }

    private var storageRecoveryState: some View {
        ContentUnavailableView(
            session.text("localStorageUnavailableTitle"),
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(session.text("localStorageUnavailableMessage"))
        )
        .cardSurface(padding: AppSpacing.large, cornerRadius: AppRadius.feature)
        .frame(maxWidth: 560)
        .padding(AppSpacing.standard)
    }

    private func remove(at offsets: IndexSet, from entries: [SavedOpportunityEntry]) {
        guard storageAccess.allowsPersistentChanges else { return }
        for index in offsets {
            modelContext.delete(entries[index].record)
        }
        do {
            try modelContext.save()
            SavedOpportunityLibrary.syncWatch(in: modelContext)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = session.text("serverResponseInvalid")
        }
    }
}

private struct SavedOpportunityEntry: Identifiable {
    let record: SavedOpportunityRecord
    let opportunity: Opportunity

    var id: String { record.opportunityID }
}

private struct SavedOpportunityListItem: View {
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: opportunity) {
                SavedOpportunityRow(opportunity: opportunity)
            }

            if let sourceURL = ExternalOpportunityURL.make(from: opportunity.sourceUrl) {
                Link(destination: sourceURL) {
                    Label(session.text("source"), systemImage: "arrow.up.right.square")
                        .font(PortfolioTypography.caption.weight(.semibold))
                        .foregroundStyle(Brand.lake)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(session.text("source")): \(session.title(for: opportunity))")
                .accessibilityHint(session.text("sourceDetails"))
            }
        }
    }
}

private struct SavedOpportunityRow: View {
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity

    var body: some View {
        OpportunityRow(opportunity: opportunity, showsDisclosure: false)
            .padding(.vertical, 8)
    }
}
