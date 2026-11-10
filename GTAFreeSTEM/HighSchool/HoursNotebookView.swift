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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: HoursDraft?
    @State private var deleting: YouthHub.HoursEntry?
    @State private var exportDocument: HoursCSVDocument?
    @State private var exporting = false
    @State private var exportGeneration: UUID?
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text(session.text("hsHoursNotebook")).font(PortfolioTypography.caption)
                Text(session.text("hsActualCompletedTime")).font(PortfolioTypography.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(session.text("hsOwnRecordsNotice"))
                    .font(PortfolioTypography.body)
                if let archive = youth.archive {
                    let minutes = archive.entries.reduce(0) { $0 + $1.actualMinutes }
                    Text(SchoolLocalized.format(session, "hsTotalFormat", ["hours": SchoolLocalized.number(minutes / 60, session), "minutes": SchoolLocalized.number(minutes % 60, session)]))
                        .font(PortfolioTypography.title2.weight(.bold)).accessibilityIdentifier("hours-recorded-total")
                    if archive.entries.isEmpty { Text(session.text("hsRecordAfterCompletion")) }
                    ForEach(archive.entries.sorted { $0.activityLocalDate > $1.activityLocalDate }, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.role).font(PortfolioTypography.headline)
                            Text(entry.provider).font(PortfolioTypography.body)
                            Text(SchoolLocalized.format(session, "hsEntryMinutesFormat", ["date": SchoolLocalized.localDate(entry.activityLocalDate, session), "minutes": SchoolLocalized.number(entry.actualMinutes, session)])).font(PortfolioTypography.subheadline)
                            if !entry.notes.isEmpty { Text(entry.notes).font(PortfolioTypography.callout) }
                            HStack {
                                Button(session.text("hsEdit")) { draft = HoursDraft(entry: entry) }.accessibilityIdentifier("hours-edit-\(entry.id)")
                                Spacer()
                                Button(session.text("hsDelete"), role: .destructive) { deleting = entry }
                            }.buttonStyle(StoryButtonStyle(kind: .quiet))
                                .disabled(!storageAccess.allowsPersistentChanges || youth.busy)
                        }.frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                    }
                }
                if let message = youth.notebookError {
                    Text(SchoolLocalized.message(message, session)).foregroundStyle(Brand.coral).accessibilityIdentifier("hours-storage-error")
                }
                Button(session.text("hsReloadNotebook")) { Task { await youth.reloadNotebook() } }
                    .buttonStyle(StoryButtonStyle(kind: .quiet)).disabled(youth.busy)
                Button(session.text("hsRecordCompletedWork")) { draft = HoursDraft(entry: nil) }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                    .disabled(!storageAccess.allowsPersistentChanges || youth.archive == nil || youth.busy || youth.notebookError != nil)
                    .accessibilityIdentifier("hours-add")
                Button(session.text("hsExportCSV")) {
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
        .background(StorybookBackground()).navigationTitle(session.text("hsMyCompletedHours")).navigationBarTitleDisplayMode(.inline)
        .task { await youth.reloadNotebook() }
        .onChange(of: youth.resetID) { _, _ in
            draft = nil; deleting = nil; exportDocument = nil; exporting = false; exportMessage = nil; exportGeneration = nil
        }
        .sheet(item: $draft) { value in
            HoursEntryEditor(youth: youth, existing: value.entry)
                .environment(\.appStorageAccess, storageAccess)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .confirmationDialog(session.text("hsDeleteEntryConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(session.text("hsDeleteEntry"), role: .destructive) {
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
            case .success: exportMessage = session.text("hsExportSuccess")
            case .failure(let error):
                if (error as NSError).code != CocoaError.Code.userCancelled.rawValue { exportMessage = session.text("hsExportFailed") }
            }
        }
    }
}

private struct HoursEntryEditor: View {
    @EnvironmentObject private var session: SessionStore
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
                    TextField(session.text("hsProviderOrganisation"), text: $provider).accessibilityIdentifier("hours-provider").focused($focused, equals: .provider)
                    TextField(session.text("hsCompletedWork"), text: $role).accessibilityIdentifier("hours-role").focused($focused, equals: .role)
                    DatePicker(session.text("hsActivityDate"), selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField(session.text("hsActualMinutes"), text: $minutes).accessibilityIdentifier("hours-minutes").keyboardType(.numberPad).focused($focused, equals: .minutes)
                    TextField(session.text("hsNotesOptional"), text: $notes, axis: .vertical).accessibilityIdentifier("hours-notes").focused($focused, equals: .notes)
                } header: {
                    Text(session.text("hsSelfRecordedWork"))
#if DEBUG
                        .accessibilityIdentifier("hours-editor-type-size")
                        .accessibilityValue(dynamicTypeSize >= .accessibility3 ? "accessibility3-or-larger" : "below-accessibility3")
#endif
                }
                Section {
                    Text(session.text("hsActualTimeSchoolDecision"))
                    if let error = youth.notebookError {
                        Text(SchoolLocalized.message(error, session)).foregroundStyle(Brand.coral).accessibilityIdentifier("hours-draft-error")
                        Button(session.text("hsReloadPreserveDraft")) { Task { await youth.reloadNotebook() } }
                            .disabled(youth.busy)
                    }
                    if let latest = youth.archive?.entries.first(where: { $0.id == draftID }), base == nil || latest.revision != base?.revision {
                        Button(session.text("hsUseLatestInstead")) { replaceDraft = true }.disabled(youth.busy)
                    }
                    Button(youth.busy ? session.text("hsSaving") : session.text("hsSaveCompletedWork")) {
                        guard let count = SchoolLocalized.enteredMinutes(minutes), (1...1440).contains(count) else { return }
                        let timestamp = youth.timestamp
                        let entry = YouthHub.HoursEntry(id: draftID, revision: (base?.revision ?? 0) + 1,
                            curatedRoleId: base?.curatedRoleId, provider: provider, role: role,
                            activityLocalDate: Self.formatter.string(from: date), actualMinutes: count, notes: notes,
                            createdAt: createdAt, updatedAt: timestamp)
                        Task { if await youth.save(entry, expectedRevision: base?.revision, writable: storageAccess.allowsPersistentChanges, generation: editorGeneration) { dismiss() } }
                    }.disabled(!storageAccess.allowsPersistentChanges || youth.busy || provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || SchoolLocalized.enteredMinutes(minutes).map { !(1...1440).contains($0) } != false)
                        .accessibilityIdentifier("hours-save")
                }
            }
            .scrollContentBackground(.hidden).background(StorybookBackground())
            .font(PortfolioTypography.body)
            .navigationTitle(base == nil ? session.text("hsAddHours") : session.text("hsEditHours"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.text("hsCancel")) { if dirty { discard = true } else { dismiss() } }.disabled(youth.busy)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(session.text("done")) { focused = nil }.accessibilityIdentifier("hours-keyboard-done") }
            }
            .interactiveDismissDisabled(dirty || youth.busy)
            .onChange(of: youth.resetID) { _, _ in
                focused = nil
                provider = ""; role = ""; notes = ""; minutes = ""; base = nil
                dismiss()
            }
            .confirmationDialog(session.text("hsDiscardDraftConfirm"), isPresented: $discard, titleVisibility: .visible) {
                Button(session.text("hsDiscardDraft"), role: .destructive) { dismiss() }
            }
            .confirmationDialog(session.text("hsReplaceDraftConfirm"), isPresented: $replaceDraft, titleVisibility: .visible) {
                Button(session.text("hsUseLatestSaved"), role: .destructive) {
                    if let latest = youth.archive?.entries.first(where: { $0.id == draftID }) {
                        base = latest; createdAt = latest.createdAt; provider = latest.provider; role = latest.role; notes = latest.notes
                        minutes = String(latest.actualMinutes); date = Self.formatter.date(from: latest.activityLocalDate) ?? date
                    }
                }
            }
        }
        .environment(\.locale, Locale(identifier: session.language.localeIdentifier)).environment(\.layoutDirection, session.language.layoutDirection)
    }
}
