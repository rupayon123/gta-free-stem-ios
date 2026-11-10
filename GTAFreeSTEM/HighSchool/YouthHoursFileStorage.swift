import Foundation
import Darwin

/// One process-wide writer, shared by all app/Catalyst windows. No app-group or Watch access.
actor YouthHoursFileStorage: YouthHoursAtomicStorage {
    static let shared = YouthHoursFileStorage(fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("GTAFreeSTEM/actual-hours-v1.json"))
    private let fileURL: URL?
    private let beforeRead: @Sendable () async -> Void
    private let beforeCAS: @Sendable () async -> Void
    private let beforeReplace: @Sendable () throws -> Void

    init(fileURL: URL?, beforeRead: @escaping @Sendable () async -> Void = {},
         beforeCAS: @escaping @Sendable () async -> Void = {},
         beforeReplace: @escaping @Sendable () throws -> Void = {}) {
        self.fileURL = fileURL
        self.beforeReplace = beforeReplace
        self.beforeRead = beforeRead; self.beforeCAS = beforeCAS
    }

    private func raw() throws -> String? {
        guard let fileURL else { throw CocoaError(.fileReadNoSuchFile) }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, YouthHub.Notebook.maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            if data.count > YouthHub.Notebook.maximumBytes { break }
        }
        guard data.count <= YouthHub.Notebook.maximumBytes,
              let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    private func locked<T>(_ action: () throws -> T) throws -> T {
        guard let fileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let lockURL = directory.appendingPathComponent("." + fileURL.lastPathComponent + ".lock")
        // O_EXLOCK acquires the same open-file-description lock atomically at open.
        // Closing the descriptor releases it, including on thrown/cancelled operations.
        let lock = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_EXLOCK, mode_t(0o600))
        guard lock >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(lock) }
        return try action()
    }
    private var epochURL: URL? { fileURL.map { $0.deletingLastPathComponent().appendingPathComponent("." + $0.lastPathComponent + ".epoch") } }
    private func epoch() throws -> UUID {
        guard let epochURL else { throw CocoaError(.fileReadInvalidFileName) }
        guard FileManager.default.fileExists(atPath: epochURL.path) else {
            return UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        }
        let data = try Data(contentsOf: epochURL, options: .mappedIfSafe)
        guard data.count == 36, let text = String(data: data, encoding: .utf8), let value = UUID(uuidString: text) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
    func lease() throws -> UUID { try locked { try epoch() } }
    func isCurrent(_ lease: UUID) throws -> Bool { try locked { try epoch() == lease } }

    func read(key: String) async throws -> String? { try await read(key: key, lease: nil) }
    func read(key: String, lease: UUID?) async throws -> String? {
        await beforeRead()
        guard key == YouthHub.Notebook.key else { throw CocoaError(.fileReadInvalidFileName) }
        return try locked {
            if let lease, try epoch() != lease { throw YouthHub.NotebookFailure.conflict }
            return try raw()
        }
    }
    func compareAndSwap(key: String, expected: String?, replacement: String) async throws -> Bool {
        try await compareAndSwap(key: key, expected: expected, replacement: replacement, lease: nil)
    }
    func compareAndSwap(key: String, expected: String?, replacement: String, lease: UUID?) async throws -> Bool {
        await beforeCAS()
        guard let fileURL, key == YouthHub.Notebook.key, replacement.utf8.count <= YouthHub.Notebook.maximumBytes else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return try locked {
            if let lease, try epoch() != lease { return false }
            let directory = fileURL.deletingLastPathComponent()
            // No suspension between comparison and replacement: actor reentrancy cannot split CAS.
            switch (try raw(), expected) {
            case (nil, nil): break
            case let (current?, prior?):
                guard Data(current.utf8) == Data(prior.utf8) else { return false }
            default: return false
            }
            try Task.checkCancellation()
            let temporary = directory.appendingPathComponent(".hours-\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Data(replacement.utf8).write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let handle = try FileHandle(forWritingTo: temporary)
            do { try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); throw error }
            try beforeReplace()
            try Task.checkCancellation()
            guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let descriptor = Darwin.open(directory.path, O_RDONLY)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return true
        }
    }
    /// Keep only non-personal epoch/lock metadata, so stale nil/empty CAS cannot resurrect deleted records.
    func reset() throws {
        try locked {
            guard let fileURL, let epochURL else { throw CocoaError(.fileWriteInvalidFileName) }
            try atomicMetadata(Data(UUID().uuidString.utf8), to: epochURL)
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            try syncDirectory(fileURL.deletingLastPathComponent())
        }
    }
    private func atomicMetadata(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".epoch-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
        try syncDirectory(url.deletingLastPathComponent())
    }
    private func syncDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw POSIXError(.EIO) }
    }
}

private struct LeasedHoursStorage: YouthHoursAtomicStorage {
    let storage: YouthHoursFileStorage
    let lease: UUID
    func read(key: String) async throws -> String? { try await storage.read(key: key, lease: lease) }
    func compareAndSwap(key: String, expected: String?, replacement: String) async throws -> Bool {
        try await storage.compareAndSwap(key: key, expected: expected, replacement: replacement, lease: lease)
    }
}

/// Parsing, validation and durable transactions stay on this actor, not the UI executor.
actor HighSchoolRepository {
    static let shared = HighSchoolRepository(storage: YouthHoursFileStorage.shared,
        catalogueURL: Bundle.main.url(forResource: "youth-reviewed", withExtension: "json"))
    private let storage: YouthHoursFileStorage
    private let catalogueURL: URL?
    init(storage: YouthHoursFileStorage, catalogueURL: URL?) {
        self.storage = storage; self.catalogueURL = catalogueURL
    }
    func catalogue() throws -> [YouthHub.Listing] {
        guard let catalogueURL else { throw CocoaError(.fileNoSuchFile) }
        return try YouthHub.decodeCatalogue(Data(contentsOf: catalogueURL))
    }
    struct Snapshot: Sendable {
        let lease: UUID
        let archive: YouthHub.HoursArchive
    }
    func load(today: String) async -> Result<Snapshot, YouthHub.NotebookFailure> {
        do {
            let lease = try await storage.lease()
            let result = await YouthHub.Notebook.load(LeasedHoursStorage(storage: storage, lease: lease), today: today)
            guard try await storage.isCurrent(lease) else { return .failure(.conflict) }
            return result.map { Snapshot(lease: lease, archive: $0) }
        } catch { return .failure(.readFailed) }
    }
    func save(_ entry: YouthHub.HoursEntry, today: String, expectedRevision: Int?, lease: UUID) async -> Result<YouthHub.HoursArchive, YouthHub.NotebookFailure> {
        let result = await YouthHub.Notebook.save(LeasedHoursStorage(storage: storage, lease: lease), entry: entry, today: today, expectedRevision: expectedRevision)
        return await checked(result, lease: lease)
    }
    func delete(_ entry: YouthHub.HoursEntry, today: String, lease: UUID) async -> Result<YouthHub.HoursArchive, YouthHub.NotebookFailure> {
        let result = await YouthHub.Notebook.delete(LeasedHoursStorage(storage: storage, lease: lease), id: entry.id, today: today, expectedRevision: entry.revision)
        return await checked(result, lease: lease)
    }
    private func checked<T: Sendable>(_ result: Result<T, YouthHub.NotebookFailure>, lease: UUID) async -> Result<T, YouthHub.NotebookFailure> {
        do { return try await storage.isCurrent(lease) ? result : .failure(.conflict) }
        catch { return .failure(.readFailed) }
    }
    func reset() async throws { try await storage.reset() }
    func latestCSV(today: String, lease: UUID) async -> Result<String, YouthHub.NotebookFailure> {
        let result = await YouthHub.Notebook.load(LeasedHoursStorage(storage: storage, lease: lease), today: today)
        switch await checked(result, lease: lease) {
        case .failure(let error): return .failure(error)
        case .success(let archive):
            do { return .success(try YouthHub.Notebook.csv(archive, today: today)) }
            catch { return .failure(.invalidArchive) }
        }
    }
}
