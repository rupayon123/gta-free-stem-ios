import Foundation
import XCTest
@testable import GTAFreeSTEM

/// Host-only model checks; app target/resource registration and iOS execution remain pending.
final class YouthHighSchoolTests: XCTestCase {
    private let today = "2026-10-30"
    private func fixture(_ name: String) throws -> Data {
        let bundled = Bundle(for: YouthHighSchoolTests.self).url(forResource: name, withExtension: "json", subdirectory: "HighSchoolFixtures")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("HighSchoolFixtures/\(name).json")
        return try Data(contentsOf: bundled ?? source)
    }
    func testAllFourteenPortableEvaluationsAndOriginalPolicyExpectations() throws {
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("eligibility-goldens")) as? [String: Any])
        let rows = try XCTUnwrap(packet["cases"] as? [[String: Any]])
        let policy = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("eligibility")) as? [String: Any])
        let policyRows = try XCTUnwrap(policy["cases"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 14); XCTAssertEqual(policyRows.count, 14)
        for row in rows {
            let id = try XCTUnwrap(row["id"] as? String)
            let input = try XCTUnwrap(row["input"] as? [String: Any])
            let listing = try XCTUnwrap(YouthHub.decodeCatalogue(JSONSerialization.data(withJSONObject: [input])).first)
            let context = try JSONDecoder().decode(YouthHub.EvaluationContext.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap(row["context"])))
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: YouthHub.evaluate(listing, context: context).jsonData()) as? [String: Any])
            let golden = try XCTUnwrap(row["output"] as? [String: Any])
            XCTAssertEqual(actual as NSDictionary, golden as NSDictionary, id)
            let policyRow = try XCTUnwrap(policyRows.first { $0["id"] as? String == id })
            for (key, expected) in try XCTUnwrap(policyRow["expected"] as? [String: Any]) {
                XCTAssertEqual(actual[key] as? NSObject, expected as? NSObject, "\(id).\(key)")
            }
        }
    }
    func testPortableNotebookCsvAndCalendarGolden() throws {
        let g = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("notebook-golden")) as? [String: Any])
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: try XCTUnwrap(g["archive"])), as: UTF8.self)
        let archive = try YouthHub.Notebook.decode(raw, today: today)
        XCTAssertEqual(try YouthHub.Notebook.recordedMinutes(archive, today: today), 95)
        let formatted = try YouthHub.Notebook.formatMinutes(95)
        XCTAssertEqual(formatted.hours, 1); XCTAssertEqual(formatted.minutes, 35)
        XCTAssertEqual(try YouthHub.Notebook.csv(archive, today: today), g["csv"] as? String)
        XCTAssertEqual(archive.entries[0].activityLocalDate, "2026-03-08")
        XCTAssertFalse(YouthHub.validLocalDate("2026-02-29")); XCTAssertTrue(YouthHub.validLocalDate("2024-02-29"))
    }
    private func entry(revision: Int = 1, minutes: Int = 95, notes: String = "Completed") -> YouthHub.HoursEntry {
        .init(id: "9fd00ad4-ffec-4bed-bef9-15146cd6d605", revision: revision, curatedRoleId: nil,
              provider: "Library", role: "Reading buddy", activityLocalDate: "2026-10-29", actualMinutes: minutes,
              notes: notes, createdAt: "2026-10-30T01:00:00Z", updatedAt: "2026-10-30T01:00:00Z")
    }
    func testActualMinutesRoundTripAndEqualTimestampStaleEditDelete() async throws {
        let storage = YouthHoursStorageDouble()
        _ = try await YouthHub.Notebook.save(storage, entry: entry(), today: today).get()
        let initial = try await YouthHub.Notebook.load(storage, today: today).get()
        XCTAssertEqual(initial.entries, [entry()])
        _ = try await YouthHub.Notebook.save(storage, entry: entry(revision: 2, minutes: 20), today: today, expectedRevision: 1).get()
        let prior = await storage.snapshot()
        let staleEdit = await YouthHub.Notebook.save(storage, entry: entry(revision: 2, minutes: 10), today: today, expectedRevision: 1)
        XCTAssertEqual(staleEdit, .failure(.conflict))
        let staleDelete = await YouthHub.Notebook.delete(storage, id: entry().id, today: today, expectedRevision: 1)
        XCTAssertEqual(staleDelete, .failure(.conflict))
        let after = await storage.snapshot(); XCTAssertEqual(after, prior)
        _ = try await YouthHub.Notebook.delete(storage, id: entry().id, today: today, expectedRevision: 2).get()
        let empty = try await YouthHub.Notebook.load(storage, today: today).get(); XCTAssertTrue(empty.entries.isEmpty)
    }
    func testStorageFailuresCorruptionAndCasConflictPreserveBytes() async throws {
        let storage = YouthHoursStorageDouble()
        _ = try await YouthHub.Notebook.save(storage, entry: entry(), today: today).get()
        let prior = await storage.snapshot()
        await storage.configure(writeFails: true)
        let failedWrite = await YouthHub.Notebook.save(storage, entry: entry(revision: 2), today: today, expectedRevision: 1)
        XCTAssertEqual(failedWrite, .failure(.writeFailed))
        let failedDelete = await YouthHub.Notebook.delete(storage, id: entry().id, today: today, expectedRevision: 1)
        XCTAssertEqual(failedDelete, .failure(.writeFailed))
        let after = await storage.snapshot(); XCTAssertEqual(after, prior)
        await storage.configure(conflict: true)
        let conflicted = await YouthHub.Notebook.save(storage, entry: entry(revision: 2), today: today, expectedRevision: 1)
        XCTAssertEqual(conflicted, .failure(.conflict))
        await storage.configure(raw: "{\"schemaVersion\":2,\"entries\":[]}")
        let corrupted = await YouthHub.Notebook.save(storage, entry: entry(), today: today)
        XCTAssertEqual(corrupted, .failure(.invalidArchive))
        let corruptBytes = await storage.snapshot(); XCTAssertEqual(corruptBytes, "{\"schemaVersion\":2,\"entries\":[]}")
        await storage.configure(readFails: true)
        let denied = await YouthHub.Notebook.load(storage, today: today); XCTAssertEqual(denied, .failure(.readFailed))
    }
    func testInvalidMinutesDatesDailyTotalsAndCsvFormulaSafety() throws {
        for minutes in [0, -1, 1441] { XCTAssertThrowsError(try YouthHub.Notebook.validate(entry(minutes: minutes), today: today)) }
        var future = entry(); future.activityLocalDate = "2026-10-31"
        XCTAssertThrowsError(try YouthHub.Notebook.validate(future, today: today))
        var second = entry(minutes: 700); second.id = "095bd3dc-33e2-4ea9-b060-d09b90aa4700"
        XCTAssertThrowsError(try YouthHub.Notebook.validate(.init(entries: [entry(minutes: 800), second]), today: today))
        for payload in ["=HYPERLINK(\"https://example.org\")", "+SUM(1,2)", "-2+3", "@SUM(A1)", " \t=1+1", "\r=1+1", "\u{FEFF}=1+1", "One, \"two\"\nবাংলা"] {
            let e = entry(notes: payload)
            let csv = try YouthHub.Notebook.csv(.init(entries: [e]), today: today)
            XCTAssertTrue(csv.contains("\"'" + payload.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
            XCTAssertEqual(e.notes, payload)
        }
    }
    func testSourceUrlAndExplicitNullGuards() throws {
        for url in ["https://127.0.0.1/", "https://10.0.0.1/", "https://0x7f000001/", "https://device.local/", "https://user:password@example.org/", "javascript:alert(1)"] { XCTAssertFalse(YouthHub.safeSourceURL(url)) }
        XCTAssertTrue(YouthHub.safeSourceURL("https://example.org/provider"))
        XCTAssertThrowsError(try YouthHub.decodeCatalogue(Data("[{\"audience\":null}]".utf8)))
    }
    func testKnownOptionalNullsUnknownMetadataAndEcmaWhitespace() throws {
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("eligibility-goldens")) as? [String: Any])
        let rows = try XCTUnwrap(packet["cases"] as? [[String: Any]])
        var input = try XCTUnwrap(rows.first?["input"] as? [String: Any])
        input["metadata"] = ["unknown": NSNull()]
        var audience = try XCTUnwrap(input["audience"] as? [String: Any])
        audience["metadata"] = NSNull(); input["audience"] = audience
        XCTAssertEqual(try YouthHub.decodeCatalogue(JSONSerialization.data(withJSONObject: [input])).count, 1)
        audience["ageMin"] = NSNull(); input["audience"] = audience
        XCTAssertThrowsError(try YouthHub.decodeCatalogue(JSONSerialization.data(withJSONObject: [input])))
        XCTAssertTrue(YouthHub.text("\u{0085}"), "JS trim preserves NEXT LINE")
        XCTAssertTrue(YouthHub.text("\u{200B}"), "JS trim preserves ZERO WIDTH SPACE")
        for scalar in [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680,
                       0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
                       0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF] {
            XCTAssertFalse(YouthHub.text(String(try XCTUnwrap(UnicodeScalar(scalar)))))
        }
        XCTAssertThrowsError(try YouthHub.Notebook.decode("{\"schemaVersion\":1,\"entries\":[],\"unknown\":null}", today: today))
    }
    func testClockBoundariesMandatoryCostsAndHeldOrPastSeasonSources() throws {
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("eligibility-goldens")) as? [String: Any])
        let rows = try XCTUnwrap(packet["cases"] as? [[String: Any]])
        let input = try XCTUnwrap(rows.first?["input"] as? [String: Any])
        var row = try XCTUnwrap(YouthHub.decodeCatalogue(JSONSerialization.data(withJSONObject: [input])).first)
        let clock = YouthHub.EvaluationContext(now: "2026-10-29T12:00:00-04:00")
        row.availability.opensAt = clock.now
        row.availability.closesAt = "2026-10-30T12:00:00-04:00"
        XCTAssertTrue(try YouthHub.evaluate(row, context: clock).applyNow)
        XCTAssertEqual(try YouthHub.evaluate(row, context: .init(now: "2026-10-30T12:00:00-04:00")).effectiveStatus, .closed)
        row.reviewStatus = .hold
        XCTAssertFalse(try YouthHub.evaluate(row, context: clock).reviewed, "Strides staging lead stays held")
        row.reviewStatus = .approved; row.availability.seasonEndsOn = "2026-08-31"
        XCTAssertEqual(try YouthHub.evaluate(row, context: clock).effectiveStatus, .closed, "No invented next CVC season")
        row.availability.seasonEndsOn = nil; row.availability.conflicting = true
        XCTAssertFalse(try YouthHub.evaluate(row, context: clock).applyNow)
        row.availability.conflicting = false
        row.cost.requiredCosts = [.init(description: "Required screening", mandatory: true, amount: 20, currency: "CAD")]
        XCTAssertEqual(try YouthHub.evaluate(row, context: clock).costLabel, "Required cost")
        XCTAssertFalse(try YouthHub.evaluate(row, context: clock).verifiedFreeRoles)
        XCTAssertFalse(try YouthHub.evaluate(row, context: .init(now: "2026-11-29T12:00:00-05:00")).evidenceCurrent)
    }
}

private actor YouthHoursStorageDouble: YouthHoursAtomicStorage {
    private var raw: String?
    private var writeFails = false
    private var readFails = false
    private var conflict = false
    enum Failure: Error { case denied }
    func configure(raw: String? = nil, writeFails: Bool = false, readFails: Bool = false, conflict: Bool = false) {
        if let raw { self.raw = raw }; self.writeFails = writeFails; self.readFails = readFails; self.conflict = conflict
    }
    func snapshot() -> String? { raw }
    func read(key: String) throws -> String? { if readFails { throw Failure.denied }; return raw }
    func compareAndSwap(key: String, expected: String?, replacement: String) throws -> Bool {
        if writeFails { throw Failure.denied }
        guard !conflict, raw == expected else { return false }
        raw = replacement; return true
    }
}
