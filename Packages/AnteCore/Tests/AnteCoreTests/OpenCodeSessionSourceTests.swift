// Packages/AnteCore/Tests/AnteCoreTests/OpenCodeSessionSourceTests.swift
import XCTest
import SQLite3
@testable import AnteCore

final class OpenCodeSessionSourceTests: XCTestCase {
    private func makeDatabase(_ statements: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-oc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements { XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql) }
        return url
    }

    func testScanListsTopLevelUnarchivedSessionsNewestFirst() throws {
        let db = try makeDatabase([
            "CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT, title TEXT NOT NULL, directory TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, time_archived INTEGER)",
            "INSERT INTO session VALUES ('ses_aaaaaaaa1', 'p', NULL, 'How to uninstall Muse', '/Users/t/proj', 1767802771000, 1767803092000, NULL)",
            "INSERT INTO session VALUES ('ses_bbbbbbbb2', 'p', NULL, '  ', '/Users/t/other', 1767700000000, 1767900000000, NULL)",
            "INSERT INTO session VALUES ('ses_cccccccc3', 'p', 'ses_aaaaaaaa1', 'subagent', '/Users/t/proj', 1767802771000, 1767803092000, NULL)",
            "INSERT INTO session VALUES ('ses_dddddddd4', 'p', NULL, 'archived', '/Users/t/proj', 1767802771000, 1767803092000, 1767900000000)",
            "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER, time_created INTEGER NOT NULL, time_updated INTEGER, data TEXT)",
            "INSERT INTO session_message VALUES ('m1', 'ses_aaaaaaaa1', 'user', 1, 1767802771000, 1767802771000, '{}')",
            "INSERT INTO session_message VALUES ('m2', 'ses_aaaaaaaa1', 'assistant', 2, 1767802780000, 1767802780000, '{}')",
        ])
        let source = OpenCodeSessionSource(database: db)
        let sessions = source.scan()
        XCTAssertEqual(sessions.map(\.id), ["ses_bbbbbbbb2", "ses_aaaaaaaa1"], "newest first; subagent and archived rows skipped")
        XCTAssertEqual(sessions[1].title, "How to uninstall Muse")
        XCTAssertEqual(sessions[0].title, "Untitled session", "blank titles get a name")
        XCTAssertEqual(sessions[1].projectPath, "/Users/t/proj")
        XCTAssertEqual(sessions[1].agent, .opencode)
        XCTAssertEqual(sessions[1].resumeCommand, "opencode --session ses_aaaaaaaa1")
        XCTAssertEqual(sessions[1].createdAt.timeIntervalSince1970, 1767802771, accuracy: 0.001)
        let events = source.events()
        XCTAssertEqual(events.count, 1, "only the user's prompts count as activity")
        XCTAssertEqual(events.first?.sessionID, "ses_aaaaaaaa1")
    }

    func testMissingOrForeignDatabaseYieldsNothing() throws {
        XCTAssertTrue(OpenCodeSessionSource(database: URL(fileURLWithPath: "/nonexistent/opencode.db")).scan().isEmpty)
        let db = try makeDatabase(["CREATE TABLE something_else (x INTEGER)"])
        XCTAssertTrue(OpenCodeSessionSource(database: db).scan().isEmpty, "a schema we do not know is not an error")
    }
}
