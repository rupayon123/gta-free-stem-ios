import SwiftUI
import UniformTypeIdentifiers

struct HoursCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct HoursDraft: Identifiable {
    let id = UUID()
    let entry: YouthHub.HoursEntry?
}

struct HoursNotebookView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject var youth: HighSchoolHubStore
    @Environment(\.appStorageAccess) private var storageAccess
    @Environment(\.colorScheme) private var scheme
    @State private var draft: HoursDraft?
    @State private var deleting: YouthHub.HoursEntry?
    @State private var exportDocument: HoursCSVDocument?
    @State private var exporting = false
    @State private var exportGeneration: UUID?
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Hours notebook").font(PortfolioTypography.caption)
                if session.language != .en {
                    Text("The notebook is currently in English. App navigation stays in your selected language.")
                        .font(PortfolioTypography.footnote).accessibilityIdentifier("hours-untranslated-notice")
                }
                Text("Actual completed time").font(PortfolioTypography.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text("These are your own records, not a signed school form or confirmation of approved hours.")
                    .font(PortfolioTypography.body)
                if let archive = youth.archive {
                    let minutes = archive.entries.reduce(0) { $0 + $1.actualMinutes }
                    Text("\(minutes / 60) h \(minutes % 60) min self-recorded")
                        .font(PortfolioTypography.title2.weight(.bold)).accessibilityIdentifier("hours-recorded-total")
                    if archive.entries.isEmpty { Text("Record work after you complete it. No scheduled time is added automatically.") }
                    ForEach(archive.entries.sorted { $0.activityLocalDate > $1.activityLocalDate }, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.role).font(PortfolioTypography.headline)
                            Text(entry.provider).font(PortfolioTypography.body)
                            Text("\(entry.activityLocalDate) · \(entry.actualMinutes) actual minutes").font(PortfolioTypography.subheadline)
                            if !entry.notes.isEmpty { Text(entry.notes).font(PortfolioTypography.callout) }
                            HStack {
                                Button("Edit") { draft = HoursDraft(entry: entry) }.accessibilityIdentifier("hours-edit-\(entry.id)")
                                Spacer()
                                Button("Delete", role: .destructive) { deleting = entry }
                            }.buttonStyle(StoryButtonStyle(kind: .quiet))
                                .disabled(!storageAccess.allowsPersistentChanges || youth.busy)
                        }.frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                    }
                }
                if let message = youth.notebookError {
                    Text(message).foregroundStyle(Brand.coral).accessibilityIdentifier("hours-storage-error")
                }
                Button("Reload latest saved notebook") { Task { await youth.reloadNotebook() } }
                    .buttonStyle(StoryButtonStyle(kind: .quiet)).disabled(youth.busy)
                Button("Record completed work") { draft = HoursDraft(entry: nil) }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                    .disabled(!storageAccess.allowsPersistentChanges || youth.archive == nil || youth.busy || youth.notebookError != nil)
                    .accessibilityIdentifier("hours-add")
                Button("Export latest saved records as CSV") {
                    let generation = youth.resetID
                    Task {
                        exportGeneration = generation; exportDocument = nil; exportMessage = nil
                        if let csv = await youth.latestCSV(generation: generation), youth.resetID == generation { exportDocument = HoursCSVDocument(text: csv); exporting = true }
                    }
                }.buttonStyle(StoryButtonStyle(kind: .secondary)).disabled(youth.archive == nil || youth.busy)
                    .accessibilityIdentifier("hours-export-latest")
                if let exportMessage { Text(exportMessage).font(PortfolioTypography.footnote) }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(StorybookBackground()).navigationTitle("My completed hours").navigationBarTitleDisplayMode(.inline)
        .task { await youth.reloadNotebook() }
        .onChange(of: youth.resetID) { _, _ in
            draft = nil; deleting = nil; exportDocument = nil; exporting = false; exportMessage = nil; exportGeneration = nil
        }
        .sheet(item: $draft) { value in
            HoursEntryEditor(youth: youth, existing: value.entry)
                .environment(\.appStorageAccess, storageAccess)
        }
        .confirmationDialog("Delete this self-recorded entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                if let entry = deleting {
                    let generation = youth.resetID
                    Task { await youth.delete(entry, writable: storageAccess.allowsPersistentChanges, generation: generation) }
                }
                deleting = nil
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "gta-hours-notebook") { result in
            guard exportGeneration == youth.resetID else { return }
            switch result {
            case .success: exportMessage = "Exported the latest saved records. This is not school approval."
            case .failure(let error):
                if (error as NSError).code != CocoaError.Code.userCancelled.rawValue { exportMessage = "The export did not complete. Your notebook is unchanged." }
            }
        }
    }
}

private struct HoursEntryEditor: View {
    @ObservedObject var youth: HighSchoolHubStore
    @Environment(\.appStorageAccess) private var storageAccess
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editorGeneration: UUID
    private let initialLocalDate: String
    @State private var draftID: String
    @State private var createdAt: String
    @State private var base: YouthHub.HoursEntry?
    @State private var provider: String
    @State private var role: String
    @State private var minutes: String
    @State private var notes: String
    @State private var date: Date
    @State private var discard = false
    @State private var replaceDraft = false
    private enum EntryField: Hashable { case provider, role, minutes, notes }
    @FocusState private var focused: EntryField?

    init(youth: HighSchoolHubStore, existing: YouthHub.HoursEntry?) {
        self.youth = youth
        _editorGeneration = State(initialValue: youth.resetID)
        _draftID = State(initialValue: existing?.id ?? UUID().uuidString.lowercased())
        _createdAt = State(initialValue: existing?.createdAt ?? youth.timestamp)
        _base = State(initialValue: existing)
        _provider = State(initialValue: existing?.provider ?? "")
        _role = State(initialValue: existing?.role ?? "")
        _minutes = State(initialValue: existing.map { String($0.actualMinutes) } ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        let initialDate = existing.flatMap { Self.formatter.date(from: $0.activityLocalDate) } ?? Date()
        initialLocalDate = Self.formatter.string(from: initialDate)
        _date = State(initialValue: initialDate)
    }
    private static var formatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }
    private var dirty: Bool {
        provider != (base?.provider ?? "") || role != (base?.role ?? "") || notes != (base?.notes ?? "") ||
        minutes != (base.map { String($0.actualMinutes) } ?? "") ||
        Self.formatter.string(from: date) != (base?.activityLocalDate ?? initialLocalDate)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Provider / organisation", text: $provider).accessibilityIdentifier("hours-provider").focused($focused, equals: .provider)
                    TextField("Work you completed", text: $role).accessibilityIdentifier("hours-role").focused($focused, equals: .role)
                    DatePicker("Activity date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Actual minutes completed", text: $minutes).accessibilityIdentifier("hours-minutes").keyboardType(.numberPad).focused($focused, equals: .minutes)
                    TextField("Notes (optional)", text: $notes, axis: .vertical).accessibilityIdentifier("hours-notes").focused($focused, equals: .notes)
                } header: { Text("Self-recorded completed work") }
                Section {
                    Text("Enter actual time, not a provider’s estimated commitment. Your school decides eligibility and approval.")
                    if let error = youth.notebookError {
                        Text(error).foregroundStyle(Brand.coral).accessibilityIdentifier("hours-draft-error")
                        Button("Reload latest without discarding this draft") { Task { await youth.reloadNotebook() } }
                            .disabled(youth.busy)
                    }
                    if let latest = youth.archive?.entries.first(where: { $0.id == draftID }), base == nil || latest.revision != base?.revision {
                        Button("Use latest saved version instead") { replaceDraft = true }.disabled(youth.busy)
                    }
                    Button(youth.busy ? "Saving…" : "Save completed work") {
                        guard let count = Int(minutes), (1...1440).contains(count) else { return }
                        let timestamp = youth.timestamp
                        let entry = YouthHub.HoursEntry(id: draftID, revision: (base?.revision ?? 0) + 1,
                            curatedRoleId: base?.curatedRoleId, provider: provider, role: role,
                            activityLocalDate: Self.formatter.string(from: date), actualMinutes: count, notes: notes,
                            createdAt: createdAt, updatedAt: timestamp)
                        Task { if await youth.save(entry, expectedRevision: base?.revision, writable: storageAccess.allowsPersistentChanges, generation: editorGeneration) { dismiss() } }
                    }.disabled(!storageAccess.allowsPersistentChanges || youth.busy || provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Int(minutes).map { !(1...1440).contains($0) } != false)
                        .accessibilityIdentifier("hours-save")
                }
            }
            .scrollContentBackground(.hidden).background(StorybookBackground())
            .font(PortfolioTypography.body)
            .navigationTitle(dynamicTypeSize >= .accessibility3
                ? (base == nil ? "Add hours" : "Edit hours")
                : (base == nil ? "Record completed work" : "Edit completed work"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(youth.busy)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil }.accessibilityIdentifier("hours-keyboard-done") }
            }
            .interactiveDismissDisabled(dirty || youth.busy)
            .onChange(of: youth.resetID) { _, _ in
                focused = nil
                provider = ""; role = ""; notes = ""; minutes = ""; base = nil
                dismiss()
            }
            .confirmationDialog("Discard this unsaved draft?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { dismiss() }
            }
            .confirmationDialog("Replace your draft with the latest saved version?", isPresented: $replaceDraft, titleVisibility: .visible) {
                Button("Use latest saved version", role: .destructive) {
                    if let latest = youth.archive?.entries.first(where: { $0.id == draftID }) {
                        base = latest; createdAt = latest.createdAt; provider = latest.provider; role = latest.role; notes = latest.notes
                        minutes = String(latest.actualMinutes); date = Self.formatter.date(from: latest.activityLocalDate) ?? date
                    }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en_CA")).environment(\.layoutDirection, .leftToRight)
    }
}
