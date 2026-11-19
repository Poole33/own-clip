import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct HistoryError: LocalizedError {
    let message: AppMessage
    init(message: @autoclosure @escaping () -> String) { self.message = AppMessage(message()) }
    var errorDescription: String? { message.text }
}

final class HistoryStore {
    let directory: URL
    private let contents: URL
    private let decoder = PropertyListDecoder()
    private let encoder = PropertyListEncoder()
    private var database: OpaquePointer?

    init(directory: URL) throws {
        self.directory = directory
        contents = directory.appendingPathComponent("Contents", isDirectory: true)
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("History.sqlite3").path
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let connection else {
            sqlite3_close(connection)
            throw HistoryError(message: AppText.text("无法打开本地历史数据库。"))
        }
        database = connection
        do {
            try execute("""
                PRAGMA secure_delete = ON;
                CREATE TABLE IF NOT EXISTS clips (
                    id TEXT PRIMARY KEY NOT NULL,
                    captured REAL NOT NULL,
                    summary BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS clips_by_date ON clips(captured DESC);
                """)
            try reclaimOrphans()
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    static func openDefault() throws -> HistoryStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        return try HistoryStore(directory: support.appendingPathComponent("OwnClip", isDirectory: true))
    }

    func history() throws -> [ClipSummary] {
        try statement("SELECT summary FROM clips ORDER BY captured DESC, id") { query in
            var summaries: [ClipSummary] = []
            while true {
                switch sqlite3_step(query) {
                case SQLITE_ROW:
                    guard let bytes = sqlite3_column_blob(query, 0) else { continue }
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
                    summaries.append(try decoder.decode(ClipSummary.self, from: data))
                case SQLITE_DONE:
                    return summaries
                default:
                    throw databaseError()
                }
            }
        }
    }

    func save(_ payload: ClipboardPayload, summary: ClipSummary) throws {
        let location = file(for: summary.id)
        let needsFile = !FileManager.default.fileExists(atPath: location.path)
        if needsFile {
            try encoder.encode(payload).write(to: location, options: [.atomic])
        }
        do {
            let bytes = try encoder.encode(summary)
            try statement("""
                INSERT INTO clips (id, captured, summary) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET captured = excluded.captured, summary = excluded.summary
                """) { query in
                try bind(summary.id, to: query, at: 1)
                guard sqlite3_bind_double(query, 2, summary.date.timeIntervalSince1970) == SQLITE_OK else {
                    throw databaseError()
                }
                try bytes.withUnsafeBytes { buffer in
                    guard sqlite3_bind_blob(query, 3, buffer.baseAddress, Int32(buffer.count), sqliteTransient) == SQLITE_OK else {
                        throw databaseError()
                    }
                }
                try finish(query)
            }
        } catch {
            if needsFile { try? FileManager.default.removeItem(at: location) }
            throw error
        }
    }

    func read(_ id: String) throws -> ClipboardPayload {
        try decoder.decode(ClipboardPayload.self, from: Data(contentsOf: file(for: id), options: .mappedIfSafe))
    }

    func remove(_ id: String) throws {
        try statement("DELETE FROM clips WHERE id = ?") { query in
            try bind(id, to: query, at: 1)
            try finish(query)
        }
        try removeFiles([id])
    }

    func purge(before cutoff: Date) throws -> Set<String> {
        let date = cutoff.timeIntervalSince1970
        let expired = try statement("SELECT id FROM clips WHERE captured <= ?") { query in
            guard sqlite3_bind_double(query, 1, date) == SQLITE_OK else { throw databaseError() }
            return try identifiers(in: query)
        }
        if !expired.isEmpty {
            try statement("DELETE FROM clips WHERE captured <= ?") { query in
                guard sqlite3_bind_double(query, 1, date) == SQLITE_OK else { throw databaseError() }
                try finish(query)
            }
            try removeFiles(expired)
        }
        return expired
    }

    func clear() throws {
        let ids = try statement("SELECT id FROM clips", identifiers)
        try execute("DELETE FROM clips")
        try removeFiles(ids)
    }

    func payloadFile(for id: String) -> URL { file(for: id) }

    private func file(for id: String) -> URL {
        contents.appendingPathComponent(id, isDirectory: false).appendingPathExtension("clip")
    }

    private func reclaimOrphans() throws {
        let knownIDs = try statement("SELECT id FROM clips", identifiers)
        let urls = try FileManager.default.contentsOfDirectory(at: contents, includingPropertiesForKeys: nil)
        for url in urls where url.pathExtension == "clip" && !knownIDs.contains(url.deletingPathExtension().lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func removeFiles(_ ids: Set<String>) throws {
        var firstFailure: Error?
        for id in ids {
            let url = file(for: id)
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                continue
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    private func identifiers(in query: OpaquePointer) throws -> Set<String> {
        var ids: Set<String> = []
        while true {
            switch sqlite3_step(query) {
            case SQLITE_ROW:
                if let value = sqlite3_column_text(query, 0) { ids.insert(String(cString: value)) }
            case SQLITE_DONE:
                return ids
            default:
                throw databaseError()
            }
        }
    }

    private func statement<T>(_ sql: String, _ action: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK, let query else {
            throw databaseError()
        }
        defer { sqlite3_finalize(query) }
        return try action(query)
    }

    private func bind(_ value: String, to query: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(query, index, value, -1, sqliteTransient) == SQLITE_OK else { throw databaseError() }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func finish(_ query: OpaquePointer) throws {
        guard sqlite3_step(query) == SQLITE_DONE else { throw databaseError() }
    }

    private func databaseError() -> HistoryError {
        let detail = sqlite3_errmsg(database).map { String(cString: $0) } ?? "SQLite"
        return HistoryError(message: AppText.format("无法更新本地历史（%@）。", detail))
    }
}
