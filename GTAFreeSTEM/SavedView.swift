import SwiftData
import SwiftUI

struct SavedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
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

                if savedEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        if !currentEntries.isEmpty {
                            Section {
                                ForEach(currentEntries) { entry in
                                    NavigationLink(value: entry.opportunity) {
                                        SavedOpportunityRow(opportunity: entry.opportunity)
                                    }
                                }
                                .onDelete { remove(at: $0, from: currentEntries) }
                            } header: {
                                Text(session.text("saved"))
                            }
                        }

                        if !archivedEntries.isEmpty {
                            Section {
                                ForEach(archivedEntries) { entry in
                                    NavigationLink(value: entry.opportunity) {
                                        SavedOpportunityRow(opportunity: entry.opportunity)
                                    }
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
                    .tint(Brand.lake)
                }
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .multilineTextAlignment(.center)

            Text(session.text("savedArchiveNote"))
                .font(.body)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: AppSpacing.large, cornerRadius: AppRadius.feature)
        .frame(maxWidth: 560)
        .padding(AppSpacing.standard)
    }

    private func remove(at offsets: IndexSet, from entries: [SavedOpportunityEntry]) {
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

private struct SavedOpportunityRow: View {
    @EnvironmentObject private var session: SessionStore
    let opportunity: Opportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.title(for: opportunity))
                .font(.headline.weight(.semibold))
            Text(session.organization(for: opportunity))
                .font(.subheadline)
                .foregroundStyle(Brand.lake)
            Label("\(session.city(for: opportunity)), \(session.region(for: opportunity))", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
