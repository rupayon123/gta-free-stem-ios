import Foundation
import Combine

@MainActor
final class HighSchoolHubStore: ObservableObject {
    static let shared = HighSchoolHubStore()
    @Published private(set) var resetID = UUID()
    private var lease: UUID?
    @Published private(set) var listings: [YouthHub.Listing] = []
    @Published private(set) var catalogueError: String?
    @Published private(set) var archive: YouthHub.HoursArchive?
    @Published private(set) var notebookError: String?
    @Published private(set) var busy = false
    private let repository: HighSchoolRepository
    private let now: () -> Date
    init(repository: HighSchoolRepository = .shared, now: @escaping () -> Date = Date.init) {
        self.repository = repository; self.now = now
    }
    var timestamp: String { ISO8601DateFormatter().string(from: now()) }
    var today: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: now())
    }
    func evaluation(_ listing: YouthHub.Listing, age: Double? = nil, grade: Int? = nil) -> YouthHub.Evaluation? {
        try? YouthHub.evaluate(listing, context: .init(now: timestamp, selectedAge: age, selectedGrade: grade))
    }
    func loadCatalogue() async {
        do { listings = try await repository.catalogue(); catalogueError = nil }
        catch { catalogueError = "The reviewed guide could not be read. Try again; no replacement listings have been created." }
    }
    func reloadNotebook() async {
        guard !busy else { return }
        let generation = resetID
        busy = true; defer { if resetID == generation { busy = false } }
        let result = await repository.load(today: today)
        guard resetID == generation else { return }
        switch result {
        case .success(let snapshot): lease = snapshot.lease; _ = accept(.success(snapshot.archive))
        case .failure(let error): _ = accept(.failure(error))
        }
    }
    @discardableResult
    private func accept(_ result: Result<YouthHub.HoursArchive, YouthHub.NotebookFailure>) -> Bool {
        switch result {
        case .success(let value): archive = value; notebookError = nil; return true
        case .failure(let error): notebookError = Self.message(error); return false
        }
    }
    func save(_ entry: YouthHub.HoursEntry, expectedRevision: Int?, writable: Bool, generation expectedGeneration: UUID) async -> Bool {
        guard expectedGeneration == resetID, writable, !busy, let lease else { return false }
        let generation = resetID
        busy = true; defer { if resetID == generation { busy = false } }
        let result = await repository.save(entry, today: today, expectedRevision: expectedRevision, lease: lease)
        guard resetID == generation else { return false }
        return accept(result)
    }
    func delete(_ entry: YouthHub.HoursEntry, writable: Bool, generation expectedGeneration: UUID) async {
        guard expectedGeneration == resetID, writable, !busy, let lease else { return }
        let generation = resetID
        busy = true; defer { if resetID == generation { busy = false } }
        let result = await repository.delete(entry, today: today, lease: lease)
        guard resetID == generation else { return }
        _ = accept(result)
    }
    func latestCSV(generation expectedGeneration: UUID) async -> String? {
        guard expectedGeneration == resetID, !busy, let lease else { return nil }
        let generation = resetID
        busy = true; defer { if resetID == generation { busy = false } }
        let result = await repository.latestCSV(today: today, lease: lease)
        guard resetID == generation else { return nil }
        switch result {
        case .success(let value): notebookError = nil; return value
        case .failure(let error): notebookError = Self.message(error); return nil
        }
    }
    func resetAll(writable: Bool) async throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        // Invalidate UI and in-flight completions before the first suspension.
        resetID = UUID(); let generation = resetID
        archive = nil; lease = nil; notebookError = nil; busy = true
        defer { if resetID == generation { busy = false } }
        do { try await repository.reset() }
        catch {
            if resetID == generation { notebookError = "Local deletion could not be confirmed. Retry Delete all local data." }
            throw error
        }
    }
    static func message(_ error: YouthHub.NotebookFailure) -> String {
        switch error {
        case .conflict: "This record changed elsewhere. Your draft is still here. Reload the latest record before choosing what to keep."
        case .invalidEntry: "Check the date, actual minutes and text. A day cannot contain more than 1,440 recorded minutes."
        case .invalidArchive: "The saved notebook has an unsupported or damaged format. Its original file has been preserved."
        case .readFailed: "The notebook could not be read. Your saved file has not been replaced."
        case .writeFailed: "The save could not be confirmed. Keep your draft and reload the latest notebook before retrying."
        case .notFound: "This record is no longer in the saved notebook. Your draft has been kept."
        }
    }
}

/// Guide choices never read or write the ordinary activity search/preset model.
struct HighSchoolGuideSelection {
    var age: Double?
    var grade: Int?
    var region: String
    var delivery: String
    func matches(_ listing: YouthHub.Listing, now: String) -> Bool {
        guard let result = try? YouthHub.evaluate(listing, context: .init(now: now, selectedAge: age, selectedGrade: grade)),
              result.teenHub, result.selectedAgeEligible != false, result.selectedGradeEligible != false,
              listing.listingKind != .providerDirectory || result.directorySection else { return false }
        let locationMatches = region.isEmpty || listing.regions == nil || listing.regions?.contains(region) == true
        let formatMatches = delivery.isEmpty || listing.delivery == nil || listing.delivery == .unknown ||
            listing.delivery?.rawValue == delivery ||
            (listing.delivery == .hybrid && (delivery == YouthHub.Delivery.virtual.rawValue || delivery == YouthHub.Delivery.inPerson.rawValue))
        return locationMatches && formatMatches
    }
}
