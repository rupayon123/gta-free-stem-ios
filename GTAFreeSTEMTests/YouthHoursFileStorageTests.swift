import Foundation
import XCTest
@testable import GTAFreeSTEM

final class YouthHoursFileStorageTests: XCTestCase {
    private let today = "2026-10-30"
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gta-hours-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("hours.json")
    }
    private func entry(revision: Int = 1, minutes: Int = 35) -> YouthHub.HoursEntry {
        .init(id: "00d40f43-0870-4b99-a426-482dcc471110", revision: revision, curatedRoleId: nil, provider: "Library",
              role: "Reading buddy", activityLocalDate: "2026-10-29", actualMinutes: minutes, notes: "Completed",
              createdAt: "2026-10-30T10:00:00Z", updatedAt: "2026-10-30T10:00:00Z")
    }
    func testRealFileReloadAndLatestCsvUseCommittedRevision() async throws {
        let file = try location()
        let storage = YouthHoursFileStorage(fileURL: file)
        let repository = HighSchoolRepository(storage: storage, catalogueURL: nil)
        let snapshot = try await repository.load(today: today).get()
        _ = try await repository.save(entry(), today: today, expectedRevision: nil, lease: snapshot.lease).get()
        let first = try await repository.load(today: today).get()
        XCTAssertEqual(first.archive.entries.first?.actualMinutes, 35)
        _ = try await repository.save(entry(revision: 2, minutes: 50), today: today, expectedRevision: 1, lease: snapshot.lease).get()
        let csv = try await repository.latestCSV(today: today, lease: snapshot.lease).get()
        XCTAssertTrue(csv.contains("\"50\"")); XCTAssertFalse(csv.contains("\"35\""))
        let reloaded = try YouthHub.Notebook.decode(String(contentsOf: file, encoding: .utf8), today: today)
        XCTAssertEqual(reloaded.entries.first?.revision, 2)
    }
    func testSharedActorSerializesCompetingRawCas() async throws {
        let file = try location(); let storage = YouthHoursFileStorage(fileURL: file)
        let seeded = try await storage.compareAndSwap(key: YouthHub.Notebook.key, expected: nil, replacement: "initial")
        XCTAssertTrue(seeded)
        async let a = storage.compareAndSwap(key: YouthHub.Notebook.key, expected: "initial", replacement: "writer-a")
        async let b = storage.compareAndSwap(key: YouthHub.Notebook.key, expected: "initial", replacement: "writer-b")
        let (left, right) = try await (a, b)
        XCTAssertEqual([left, right].filter { $0 }.count, 1)
        let latest = try await storage.read(key: YouthHub.Notebook.key)
        XCTAssertTrue(latest == "writer-a" || latest == "writer-b")
    }
    func testSeparateAdaptersForOneFileCannotLoseAConcurrentUpdate() async throws {
        let file = try location()
        let first = YouthHoursFileStorage(fileURL: file), second = YouthHoursFileStorage(fileURL: file)
        _ = try await first.compareAndSwap(key: YouthHub.Notebook.key, expected: nil, replacement: "initial")
        async let a = first.compareAndSwap(key: YouthHub.Notebook.key, expected: "initial", replacement: "first")
        async let b = second.compareAndSwap(key: YouthHub.Notebook.key, expected: "initial", replacement: "second")
        let (left, right) = try await (a, b)
        XCTAssertEqual([left, right].filter { $0 }.count, 1)
    }
    func testRawCasIsByteExactNotUnicodeCanonicalEquality() async throws {
        let storage = YouthHoursFileStorage(fileURL: try location())
        let first = "\u{00E9}", differentBytes = "e\u{0301}"
        XCTAssertEqual(first, differentBytes) // Swift equality is intentionally insufficient for raw CAS.
        let seeded = try await storage.compareAndSwap(key: YouthHub.Notebook.key, expected: nil, replacement: first)
        XCTAssertTrue(seeded)
        let replaced = try await storage.compareAndSwap(key: YouthHub.Notebook.key, expected: differentBytes, replacement: "overwrite")
        XCTAssertFalse(replaced)
        let retained = try await storage.read(key: YouthHub.Notebook.key)
        XCTAssertEqual(retained.map { Data($0.utf8) }, Data(first.utf8))
    }
    func testFailedAtomicReplacementAndUnknownArchivePreserveOriginalBytes() async throws {
        let file = try location(); let storage = YouthHoursFileStorage(fileURL: file)
        _ = try await YouthHub.Notebook.save(storage, entry: entry(), today: today).get()
        let prior = try Data(contentsOf: file)
        let failing = YouthHoursFileStorage(fileURL: file, beforeReplace: { throw CocoaError(.fileWriteOutOfSpace) })
        let result = await YouthHub.Notebook.save(failing, entry: entry(revision: 2), today: today, expectedRevision: 1)
        XCTAssertEqual(result, .failure(.writeFailed)); XCTAssertEqual(try Data(contentsOf: file), prior)
        let children = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        XCTAssertFalse(children.contains { $0.hasSuffix(".tmp") })
        let unknown = Data("{\"schemaVersion\":99,\"entries\":[]}".utf8)
        try unknown.write(to: file)
        let rejected = await YouthHub.Notebook.save(storage, entry: entry(), today: today)
        XCTAssertEqual(rejected, .failure(.invalidArchive)); XCTAssertEqual(try Data(contentsOf: file), unknown)
    }
    func testResetRejectsMissingAndEmptyArchiveLeasesAcrossAdapters() async throws {
        for seedEmpty in [false, true] {
            let file = try location()
            let first = YouthHoursFileStorage(fileURL: file)
            let other = YouthHoursFileStorage(fileURL: file)
            let repository = HighSchoolRepository(storage: first, catalogueURL: nil)
            if seedEmpty { try Data("{\"schemaVersion\":1,\"entries\":[]}".utf8).write(to: file) }
            let prior = try await repository.load(today: today).get()
            try await other.reset()
            let rejected = await repository.save(entry(), today: today, expectedRevision: nil, lease: prior.lease)
            XCTAssertEqual(rejected, .failure(.conflict))
            let staleCSV = await repository.latestCSV(today: today, lease: prior.lease)
            XCTAssertEqual(staleCSV, .failure(.conflict))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            let fresh = try await repository.load(today: today).get()
            _ = try await repository.save(entry(), today: today, expectedRevision: nil, lease: fresh.lease).get()
            let staleDelete = await repository.delete(entry(), today: today, lease: prior.lease)
            XCTAssertEqual(staleDelete, .failure(.conflict))
            let latest = try await repository.load(today: today).get()
            XCTAssertEqual(latest.archive.entries.count, 1)
        }
    }
    func testResetWhileReadSuspendedRejectsOldSnapshot() async throws {
        let gate = HoursTestGate(), file = try location()
        let storage = YouthHoursFileStorage(fileURL: file, beforeRead: { await gate.pause() })
        let repository = HighSchoolRepository(storage: storage, catalogueURL: nil)
        let day = today
        let pending = Task { [repository, day] in await repository.load(today: day) }
        await gate.reached()
        try await repository.reset()
        await gate.release()
        let result = await pending.value
        if case .success = result { XCTFail("Pre-reset read published an old lease") }
    }
    @MainActor func testResetWhileCasSuspendedClearsUiAndPreventsResurrection() async throws {
        let gate = HoursTestGate(), file = try location()
        let storage = YouthHoursFileStorage(fileURL: file, beforeCAS: { await gate.pause() })
        let repository = HighSchoolRepository(storage: storage, catalogueURL: nil)
        let store = HighSchoolHubStore(repository: repository)
        await store.reloadNotebook()
        let oldGeneration = store.resetID
        let draft = entry()
        let pending = Task { [store, draft, oldGeneration] in
            await store.save(draft, expectedRevision: nil, writable: true, generation: oldGeneration)
        }
        await gate.reached()
        try await store.resetAll(writable: true)
        XCTAssertNotEqual(store.resetID, oldGeneration); XCTAssertNil(store.archive)
        await gate.release()
        let saved = await pending.value
        XCTAssertFalse(saved); XCTAssertNil(store.archive); XCTAssertNil(store.notebookError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        await store.reloadNotebook()
        let queuedOldSave = await store.save(entry(), expectedRevision: nil, writable: true, generation: oldGeneration)
        XCTAssertFalse(queuedOldSave)
        let freshSaved = await store.save(entry(), expectedRevision: nil, writable: true, generation: store.resetID)
        XCTAssertTrue(freshSaved)
    }
    @MainActor func testReadOnlyResetPreservesFileAndCachedNotebook() async throws {
        let file = try location()
        // Use a real seeded file for the actual store under test.
        let persistent = YouthHoursFileStorage(fileURL: file)
        _ = try await YouthHub.Notebook.save(persistent, entry: entry(), today: today).get()
        let before = try Data(contentsOf: file)
        let store = HighSchoolHubStore(repository: HighSchoolRepository(storage: persistent, catalogueURL: nil))
        await store.reloadNotebook(); let generation = store.resetID
        do { try await store.resetAll(writable: false); XCTFail("Read-only reset succeeded") } catch {}
        XCTAssertEqual(store.resetID, generation); XCTAssertEqual(store.archive?.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
    @MainActor func testReadOnlyUiGuardDoesNotCreateAFile() async throws {
        let file = try location()
        let repository = HighSchoolRepository(storage: YouthHoursFileStorage(fileURL: file), catalogueURL: nil)
        let store = HighSchoolHubStore(repository: repository)
        let saved = await store.save(entry(), expectedRevision: nil, writable: false, generation: store.resetID)
        XCTAssertFalse(saved); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    @MainActor func testExplicitSchoolActivityUrlsAndPlainHubIntent() throws {
        XCTAssertFalse(ContentView.opensSchoolActivities(try XCTUnwrap(URL(string: "gtafreestem://high-school"))))
        XCTAssertTrue(ContentView.opensSchoolActivities(try XCTUnwrap(URL(string: "gtafreestem://high-school/activities"))))
        XCTAssertTrue(ContentView.opensSchoolActivities(try XCTUnwrap(URL(string: "gtafreestem://high-school?view=activities"))))
        XCTAssertEqual(AppNavigationModePolicy.mode(for: .highSchool, currentMode: .volunteer), .volunteer)
    }
    func testGuideGradeTwelveAgeEighteenYorkOnlineKeepsHybridYres() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "youth-reviewed", withExtension: "json"))
        let records = try YouthHub.decodeCatalogue(Data(contentsOf: file))
        let yres = try XCTUnwrap(records.first { $0.id == "yres-volunteer-success-program" })
        let selection = HighSchoolGuideSelection(age: 18, grade: 12, region: "York", delivery: "virtual")
        XCTAssertTrue(selection.matches(yres, now: "2026-10-30T10:00:00Z"))
        XCTAssertTrue(HighSchoolGuideSelection(age: 18, grade: 12, region: "York", delivery: "in-person").matches(yres, now: "2026-10-30T10:00:00Z"))
        var incompatible = yres; incompatible.audience.ageMax = 17
        XCTAssertFalse(selection.matches(incompatible, now: "2026-10-30T10:00:00Z"))
        var gradeMismatch = yres; gradeMismatch.audience.grades = [9, 10]
        XCTAssertFalse(selection.matches(gradeMismatch, now: "2026-10-30T10:00:00Z"))
        var held = yres; held.reviewStatus = .hold
        XCTAssertFalse(selection.matches(held, now: "2026-10-30T10:00:00Z"))
        var adults = yres; adults.audience.context = .adult; adults.audience.grades = nil
        XCTAssertFalse(selection.matches(adults, now: "2026-10-30T10:00:00Z"))
        var inPersonOnly = yres; inPersonOnly.delivery = .inPerson
        XCTAssertFalse(selection.matches(inPersonOnly, now: "2026-10-30T10:00:00Z"))
    }
    func testAppBundlesSeparateReviewedCatalogueWithoutInventedRoles() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "youth-reviewed", withExtension: "json"))
        let rows = try YouthHub.decodeCatalogue(Data(contentsOf: file))
        XCTAssertEqual(rows.count, 9)
        XCTAssertEqual(rows.filter { $0.listingKind == .role }.count, 0)
        XCTAssertEqual(rows.filter { $0.listingKind == .providerDirectory }.count, 2)
    }
}

/// Deterministic suspension without timing sleeps; all later operations pass after release.
private actor HoursTestGate {
    private var arrived = false
    private var opened = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    func pause() async {
        guard !opened else { return }
        arrived = true; arrival?.resume(); arrival = nil
        await withCheckedContinuation { blocked = $0 }
    }
    func reached() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() {
        opened = true; blocked?.resume(); blocked = nil
    }
}
