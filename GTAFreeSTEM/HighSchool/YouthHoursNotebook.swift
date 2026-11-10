import Foundation

/// Adapter must atomically compare/read/write across every writer, acknowledging
/// only the completed durable transaction. No UserDefaults get/set substitute.
protocol YouthHoursAtomicStorage: Sendable {
    func read(key: String) async throws -> String?
    func compareAndSwap(key: String, expected: String?, replacement: String) async throws -> Bool
}

extension YouthHub {
    enum NotebookFailure: String, Error, Sendable {
        case readFailed = "read-failed", invalidArchive = "invalid-archive", invalidEntry = "invalid-entry"
        case writeFailed = "write-failed", conflict, notFound = "not-found"
    }
    struct HoursEntry: Codable, Equatable, Sendable {
        var id: String
        var revision: Int
        var curatedRoleId: String?
        var provider: String
        var role: String
        var activityLocalDate: String
        var actualMinutes: Int
        var notes: String
        var createdAt: String
        var updatedAt: String
    }
    struct HoursArchive: Codable, Equatable, Sendable { var schemaVersion = 1; var entries: [HoursEntry] }

    enum Notebook {
        static let key = "gta.highSchool.actualMinutes.v1"
        static let maximumBytes = 2_000_000
        static let maximumSafeInteger = 9_007_199_254_740_991

        static func validate(_ e: HoursEntry, today: String) throws {
            try YouthHub.require(YouthHub.validLocalDate(today), "today")
            try YouthHub.require(YouthHub.matches(e.id, #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#), "entry ID")
            try YouthHub.require(e.revision >= 1 && e.revision <= maximumSafeInteger, "revision")
            try YouthHub.require(YouthHub.text(e.provider, max: 160) && YouthHub.text(e.role, max: 160) && YouthHub.text(e.notes, max: 2000, empty: true), "entry text")
            if let role = e.curatedRoleId { try YouthHub.require(YouthHub.text(role, max: 120), "curated role") }
            try YouthHub.require(YouthHub.validLocalDate(e.activityLocalDate) && e.activityLocalDate <= today, "activity date")
            try YouthHub.require((1...1440).contains(e.actualMinutes), "actual minutes")
            guard let created = YouthHub.timestamp(e.createdAt), let updated = YouthHub.timestamp(e.updatedAt), created <= updated else { throw ValidationError.invalid("entry metadata") }
        }
        static func validate(_ archive: HoursArchive, today: String) throws {
            try YouthHub.require(YouthHub.validLocalDate(today) && archive.schemaVersion == 1 && archive.entries.count <= 2000, "archive")
            try YouthHub.require(Set(archive.entries.map(\.id)).count == archive.entries.count, "duplicate entry ID")
            var totals: [String: Int] = [:]
            for entry in archive.entries {
                try validate(entry, today: today)
                totals[entry.activityLocalDate, default: 0] += entry.actualMinutes
                try YouthHub.require(totals[entry.activityLocalDate, default: 0] <= 1440, "daily minutes")
            }
        }
        static func decode(_ raw: String?, today: String) throws -> HoursArchive {
            try YouthHub.require(YouthHub.validLocalDate(today), "today")
            guard let raw else { return HoursArchive(entries: []) }
            let data = Data(raw.utf8)
            try YouthHub.require(data.count <= maximumBytes, "archive bytes")
            let object = try JSONSerialization.jsonObject(with: data)
            try YouthHub.rejectNulls(object)
            guard let top = object as? [String: Any], Set(top.keys).isSubset(of: ["schemaVersion", "entries"]), let rows = top["entries"] as? [[String: Any]] else { throw ValidationError.invalid("archive shape") }
            let allowed: Set<String> = ["id", "revision", "curatedRoleId", "provider", "role", "activityLocalDate", "actualMinutes", "notes", "createdAt", "updatedAt"]
            try YouthHub.require(rows.allSatisfy { Set($0.keys).isSubset(of: allowed) }, "unknown entry key")
            let archive = try JSONDecoder().decode(HoursArchive.self, from: data)
            try validate(archive, today: today)
            return archive
        }
        private static func read(_ storage: any YouthHoursAtomicStorage, today: String) async -> Result<(raw: String?, archive: HoursArchive), NotebookFailure> {
            let raw: String?
            do { raw = try await storage.read(key: key) } catch { return .failure(.readFailed) }
            do { return .success((raw, try decode(raw, today: today))) } catch { return .failure(.invalidArchive) }
        }
        static func load(_ storage: any YouthHoursAtomicStorage, today: String) async -> Result<HoursArchive, NotebookFailure> {
            await read(storage, today: today).map { $0.archive }
        }
        private static func commit(_ storage: any YouthHoursAtomicStorage, prior: String?, next: HoursArchive, today: String) async -> Result<HoursArchive, NotebookFailure> {
            let raw: String
            do {
                try validate(next, today: today)
                let data = try JSONEncoder().encode(next)
                guard data.count <= maximumBytes, let string = String(data: data, encoding: .utf8) else { return .failure(.invalidEntry) }
                raw = string
            } catch { return .failure(.invalidEntry) }
            guard !Task.isCancelled else { return .failure(.writeFailed) }
            do {
                guard try await storage.compareAndSwap(key: key, expected: prior, replacement: raw) else { return .failure(.conflict) }
                return .success(next)
            } catch { return .failure(.writeFailed) }
        }
        static func save(_ storage: any YouthHoursAtomicStorage, entry: HoursEntry, today: String, expectedRevision: Int? = nil) async -> Result<HoursArchive, NotebookFailure> {
            do { try validate(entry, today: today) } catch { return .failure(.invalidEntry) }
            switch await read(storage, today: today) {
            case .failure(let error): return .failure(error)
            case .success(let loaded):
                let existing = loaded.archive.entries.first { $0.id == entry.id }
                if let existing, expectedRevision != existing.revision { return .failure(.conflict) }
                if let existing {
                    guard existing.revision < maximumSafeInteger, entry.revision == existing.revision + 1,
                          existing.createdAt == entry.createdAt,
                          let updated = YouthHub.timestamp(entry.updatedAt), let previous = YouthHub.timestamp(existing.updatedAt), updated >= previous else { return .failure(.invalidEntry) }
                } else {
                    guard entry.revision == 1 else { return .failure(.invalidEntry) }
                    guard expectedRevision == nil else { return .failure(.notFound) }
                }
                let entries = existing == nil ? loaded.archive.entries + [entry] : loaded.archive.entries.map { $0.id == entry.id ? entry : $0 }
                return await commit(storage, prior: loaded.raw, next: HoursArchive(entries: entries), today: today)
            }
        }
        static func delete(_ storage: any YouthHoursAtomicStorage, id: String, today: String, expectedRevision: Int) async -> Result<HoursArchive, NotebookFailure> {
            switch await read(storage, today: today) {
            case .failure(let error): return .failure(error)
            case .success(let loaded):
                guard let entry = loaded.archive.entries.first(where: { $0.id == id }) else { return .failure(.notFound) }
                guard entry.revision == expectedRevision else { return .failure(.conflict) }
                return await commit(storage, prior: loaded.raw, next: HoursArchive(entries: loaded.archive.entries.filter { $0.id != id }), today: today)
            }
        }
        static func recordedMinutes(_ archive: HoursArchive, today: String) throws -> Int {
            try validate(archive, today: today)
            return archive.entries.reduce(0) { $0 + $1.actualMinutes }
        }
        static func formatMinutes(_ minutes: Int) throws -> (hours: Int, minutes: Int) {
            try YouthHub.require(minutes >= 0 && minutes <= maximumSafeInteger, "total minutes")
            return (minutes / 60, minutes % 60)
        }
        private static func csvCell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        static func csv(_ archive: HoursArchive, today: String) throws -> String {
            try validate(archive, today: today)
            let header = ["Activity local date", "Provider", "Role", "Actual minutes", "Notes", "Record type"].map(csvCell).joined(separator: ",")
            let rows = archive.entries.map { entry in
                [entry.activityLocalDate, "'" + entry.provider, "'" + entry.role, String(entry.actualMinutes), "'" + entry.notes, "Self-recorded; not school approval"].map(csvCell).joined(separator: ",")
            }
            return ([header] + rows).joined(separator: "\r\n") + "\r\n"
        }
    }
}
