// Packages/AnteCore/Sources/AnteCore/Agents/OpenCodeSessionSource.swift
import Foundation
import SQLite3

/// OpenCode keeps everything in one SQLite file (`~/.local/share/opencode/opencode.db`):
/// a `session` row per conversation and `session_message` rows under it. Read-only, opened as
/// immutable so a running OpenCode (WAL mode) is never blocked or blocking.
public struct OpenCodeSessionSource: Sendable {
    public let database: URL

    public init(database: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/share/opencode/opencode.db")) {
        self.database = database
    }

    /// Top-level, unarchived sessions, newest first. Subagent sessions (`parent_id` set) belong to
    /// their parent and are not listed.
    public func scan() -> [PastSession] {
        SQLiteReader.rows(database: database, sql: """
            SELECT id, title, directory, time_created, time_updated FROM session
            WHERE parent_id IS NULL AND time_archived IS NULL ORDER BY time_updated DESC LIMIT 1000
            """).compactMap { row in
            guard row.count >= 5, let id = row[0], let directory = row[2],
                  let created = row[3].flatMap(Double.init), let updated = row[4].flatMap(Double.init) else { return nil }
            let title = (row[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return PastSession(id: id, agent: .opencode, title: title.isEmpty ? "Untitled session" : ClaudeSessionSource.clean(title),
                               projectPath: directory, createdAt: Date(timeIntervalSince1970: created / 1000),
                               modifiedAt: Date(timeIntervalSince1970: updated / 1000), detail: nil,
                               resumeCommand: AgentKind.opencode.resumeCommand(sessionID: id))
        }
    }

    /// One event per prompt the user sent, for the Activity strip.
    public func events() -> [ActivityEvent] {
        SQLiteReader.rows(database: database, sql: """
            SELECT session_id, time_created FROM session_message WHERE type = 'user' ORDER BY time_created DESC LIMIT 200000
            """).compactMap { row in
            guard row.count >= 2, let session = row[0], let ms = row[1].flatMap(Double.init) else { return nil }
            return ActivityEvent(at: Date(timeIntervalSince1970: ms / 1000), sessionID: session, agent: .opencode)
        }
    }
}

/// The smallest possible SQLite wrapper: run one read-only query, get text cells back.
enum SQLiteReader {
    static func rows(database: URL, sql: String) -> [[String?]] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        // A plain read-only open sees everything committed, including frames still in the WAL
        // (OpenCode runs in WAL mode; readers never block its writer). `immutable=1` — which
        // ignores the WAL — is only the fallback for a store we cannot open or query normally
        // (a WAL database whose shared-memory file a reader may not create fails at prepare).
        let encoded = database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? database.path
        return query("file:\(encoded)", sql: sql) ?? query("file:\(encoded)?immutable=1", sql: sql) ?? []
    }

    /// Nil when the database cannot be opened, the statement cannot be prepared, or stepping
    /// fails part-way (so the caller's fallback gets a turn instead of a silent partial result).
    private static func query(_ uri: String, sql: String) -> [[String?]]? {
        var db: OpaquePointer?
        defer { if let db { sqlite3_close(db) } }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        var out: [[String?]] = []
        let columns = Int(sqlite3_column_count(statement))
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            out.append((0..<columns).map { i in
                sqlite3_column_type(statement, Int32(i)) == SQLITE_NULL ? nil : sqlite3_column_text(statement, Int32(i)).map { String(cString: $0) }
            })
            status = sqlite3_step(statement)
        }
        return status == SQLITE_DONE ? out : nil
    }
}
