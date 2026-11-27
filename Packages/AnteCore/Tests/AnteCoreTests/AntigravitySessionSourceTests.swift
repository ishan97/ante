import XCTest
import SQLite3
@testable import AnteCore

final class AntigravitySessionSourceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-agy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// The table as Antigravity creates it (columns the source doesn't read left out).
    private func makeDatabase(_ name: String, rows: [String]) throws -> URL {
        let url = root.appendingPathComponent("\(name).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let create = """
            CREATE TABLE conversation_summaries (conversation_id text, title text NOT NULL DEFAULT "", preview text NOT NULL DEFAULT "",
              step_count integer NOT NULL DEFAULT 0, last_modified_time datetime NOT NULL, workspace_uris text NOT NULL,
              parent_conversation_id text NOT NULL DEFAULT "", nesting_depth integer NOT NULL DEFAULT 0,
              last_user_input_time datetime NOT NULL, app_data_dir text NOT NULL DEFAULT "", PRIMARY KEY (conversation_id))
            """
        for sql in [create] + rows.map({ "INSERT INTO conversation_summaries VALUES (\($0))" }) {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return url
    }

    private let cli = "0be8de45-69fe-48db-9f4c-2c4b81320fa9"
    private let app = "da3c1c9a-841d-4bd9-9604-f031ee1c87c8"

    func testListsCLIAndAppConversationsMergedByID() throws {
        let cliDB = try makeDatabase("cli", rows: [
            "'\(cli)', '', 'Fix the   login\nbug', 2, '2026-11-27 18:04:50.061953+00:00', '[\"file:///Users/t/my%20proj\"]', '', 0, '2026-11-27 18:04:42.507712+00:00', 'antigravity-cli'",
            // The app's conversation as the CLI indexed it, older than the app's own row.
            "'\(app)', 'Folder Contents Overview', 'What do we have here?', 463, '2026-11-17 04:18:49+00:00', '[\"file:///Users/t/bible\"]', '', 0, '0001-01-01 00:00:00+00:00', 'antigravity'",
            "'aaaaaaaa-0000-4000-8000-000000000001', 'subagent', '', 3, '2026-11-27 18:00:00+00:00', '[\"file:///Users/t/x\"]', '\(cli)', 1, '0001-01-01 00:00:00+00:00', 'antigravity-cli'",
            "'aaaaaaaa-0000-4000-8000-000000000002', 'empty', '', 0, '2026-11-27 18:00:00+00:00', '[\"file:///Users/t/x\"]', '', 0, '0001-01-01 00:00:00+00:00', 'antigravity-cli'",
            "'aaaaaaaa-0000-4000-8000-000000000003', 'no folder', '', 3, '2026-11-27 18:00:00+00:00', '[]', '', 0, '0001-01-01 00:00:00+00:00', 'antigravity-cli'",
        ])
        let appDB = try makeDatabase("app", rows: [
            "'\(app)', 'Folder Contents Overview', '', 470, '2026-11-18 09:00:00.5+00:00', '[\"file:///Users/t/bible\"]', '', 0, '2026-11-16 18:31:33.744206+00:00', 'antigravity'",
        ])
        let sessions = AntigravitySessionSource(databases: [cliDB, appDB, root.appendingPathComponent("missing.db")], keepsFolder: { _ in true }).scan()
        XCTAssertEqual(sessions.map(\.id), [cli, app], "newest first; subagents, empty and folderless rows skipped; one row per id")

        let first = sessions[0]
        XCTAssertEqual(first.agent, .antigravity)
        XCTAssertEqual(first.title, "Fix the login bug", "no title: the preview, on one line")
        XCTAssertEqual(first.projectPath, "/Users/t/my proj")
        XCTAssertNil(first.detail, "a CLI conversation needs no caption")
        XCTAssertEqual(first.resumeCommand, "agy --conversation \(cli)")
        XCTAssertEqual(first.modifiedAt.timeIntervalSince1970, 1_795_802_690.061, accuracy: 0.01)
        XCTAssertEqual(first.createdAt.timeIntervalSince1970, 1_795_802_682.507, accuracy: 0.01)

        let second = sessions[1]
        XCTAssertEqual(second.title, "Folder Contents Overview")
        XCTAssertEqual(second.detail, "app")
        XCTAssertEqual(second.modifiedAt.timeIntervalSince1970, 1_794_992_400.5, accuracy: 0.01, "the newer of the two copies")
    }

    func testDatesWithAndWithoutFractions() {
        XCTAssertEqual(AntigravitySessionSource.date(from: "2026-11-17 04:18:49+00:00")?.timeIntervalSince1970, 1_794_889_129)
        XCTAssertEqual(AntigravitySessionSource.date(from: "2026-11-17 04:18:49.1+05:30")?.timeIntervalSince1970 ?? 0, 1_794_869_329.1, accuracy: 0.001)
        XCTAssertEqual(AntigravitySessionSource.date(from: "2026-11-17 04:18:49.58506+00:00")?.timeIntervalSince1970 ?? 0, 1_794_889_129.585, accuracy: 0.001)
        XCTAssertNil(AntigravitySessionSource.date(from: "yesterday"))
    }

    func testSignInComesFromTheNewestLogThatHasOne() throws {
        let logs = root.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let line = { (email: String) in "I1127 23:33:35.262986      13 server_oauth.go:221] applyAuthResult: email=\(email), authMethod=consumer, quotaProject=\n" }
        XCTAssertNil(AntigravitySignIn.read(logDirectory: logs))
        try Data(line("old@gmail.com").utf8).write(to: logs.appendingPathComponent("cli-20261101_100000.log"))
        try Data((line("first@gmail.com") + line("me@gmail.com")).utf8).write(to: logs.appendingPathComponent("cli-20261127_233334.log"))
        try Data("W1127 23:40:00 cache.go:169] You are not logged into Antigravity.\n".utf8)
            .write(to: logs.appendingPathComponent("cli-20261127_234000.log"))   // a run still starting up
        let signIn = try XCTUnwrap(AntigravitySignIn.read(logDirectory: logs))
        XCTAssertEqual(signIn.email, "me@gmail.com", "the last line of the newest log that names one")
        XCTAssertEqual(signIn.method, "consumer")
        XCTAssertEqual(signIn.at, AntigravitySignIn.startTime(of: logs.appendingPathComponent("cli-20261127_233334.log")),
                       "when that run started, from the log's name")
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: signIn.at)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second], [2026, 11, 27, 23, 33, 34])
    }

    func testSignInAtTheStartOfALongRunIsStillFound() throws {
        // A run signs in once near its start; a long session then writes megabytes after it.
        let logs = root.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("I1127 server_oauth.go:221] applyAuthResult: email=old@gmail.com, authMethod=consumer, quotaProject=\n".utf8)
            .write(to: logs.appendingPathComponent("cli-20261126_090000.log"))
        var text = "I1127 server_oauth.go:221] applyAuthResult: email=new@gmail.com, authMethod=consumer, quotaProject=\n"
        text += String(repeating: "I1127 23:40:00.000000 1 noise.go:1] working on something long and chatty\n", count: 40_000)
        XCTAssertGreaterThan(text.utf8.count, 2 * 1024 * 1024)
        try Data(text.utf8).write(to: logs.appendingPathComponent("cli-20261127_233334.log"))
        XCTAssertEqual(AntigravitySignIn.read(logDirectory: logs)?.email, "new@gmail.com", "not the previous run's account")
    }

    func testSignInFromLongAgoIsNotShown() throws {
        let logs = root.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("applyAuthResult: email=ancient@gmail.com, authMethod=consumer\n".utf8).write(to: logs.appendingPathComponent("cli-20260101_000000.log"))
        for minute in 0..<AntigravitySignIn.runsChecked {   // newer runs that never signed in (signed out)
            try Data("You are not logged into Antigravity.\n".utf8).write(to: logs.appendingPathComponent("cli-20261127_23\(String(format: "%02d", minute))00.log"))
        }
        XCTAssertNil(AntigravitySignIn.read(logDirectory: logs))
    }

    func testTemporaryAndMissingFoldersAreNotListed() throws {
        let kept = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        XCTAssertFalse(AntigravitySessionSource.isLastingFolder(kept.path), "the test's own folder is under the temporary directory")
        // Another user's temporary folder (agy runs scripts in throwaway folders like this).
        let elsewhere = URL(fileURLWithPath: AntigravitySessionSource.temporaryFoldersRoot).appendingPathComponent("zz/other/T/neon_run")
        XCTAssertFalse(AntigravitySessionSource.isLastingFolder(elsewhere.path))
        XCTAssertFalse(AntigravitySessionSource.isLastingFolder("/tmp"))
        XCTAssertFalse(AntigravitySessionSource.isLastingFolder("/Users/t/gone"), "a folder that no longer exists")
        XCTAssertTrue(AntigravitySessionSource.isLastingFolder(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    func testBattleLosersAreLeftOutAndOlderSchemasStillRead() throws {
        // The full schema: a battle's two sides, of which only the winner is listed.
        let url = root.appendingPathComponent("full.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        for sql in [
            #"CREATE TABLE conversation_summaries (conversation_id text, title text NOT NULL DEFAULT "", preview text NOT NULL DEFAULT "", step_count integer NOT NULL DEFAULT 0, last_modified_time datetime NOT NULL, workspace_uris text NOT NULL, parent_conversation_id text NOT NULL DEFAULT "", nesting_depth integer NOT NULL DEFAULT 0, last_user_input_time datetime NOT NULL, app_data_dir text NOT NULL DEFAULT "", winning_conversation_id text NOT NULL DEFAULT "")"#,
            "INSERT INTO conversation_summaries VALUES ('aaaaaaaa-0000-4000-8000-00000000000a', 'winner', '', 5, '2026-11-27 10:00:00+00:00', '[\"file:///Users/t/p\"]', '', 0, '2026-11-27 10:00:00+00:00', 'antigravity-cli', 'aaaaaaaa-0000-4000-8000-00000000000a')",
            "INSERT INTO conversation_summaries VALUES ('aaaaaaaa-0000-4000-8000-00000000000b', 'loser', '', 5, '2026-11-27 10:00:00+00:00', '[\"file:///Users/t/p\"]', '', 0, '2026-11-27 10:00:00+00:00', 'antigravity-cli', 'aaaaaaaa-0000-4000-8000-00000000000a')",
        ] { XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql) }
        sqlite3_close(db)
        XCTAssertEqual(AntigravitySessionSource(databases: [url], keepsFolder: { _ in true }).scan().map(\.title), ["winner"])

        // An older schema without the newer columns still lists its conversations.
        let old = root.appendingPathComponent("old.db")
        XCTAssertEqual(sqlite3_open(old.path, &db), SQLITE_OK)
        for sql in [
            "CREATE TABLE conversation_summaries (conversation_id text, title text NOT NULL DEFAULT '', step_count integer NOT NULL DEFAULT 0, last_modified_time datetime NOT NULL, workspace_uris text NOT NULL)",
            "INSERT INTO conversation_summaries VALUES ('aaaaaaaa-0000-4000-8000-00000000000c', 'old one', 3, '2026-01-01 10:00:00+00:00', '[\"https://example.com\", \"file:///Users/t/q\"]')",
        ] { XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql) }
        sqlite3_close(db)
        let sessions = AntigravitySessionSource(databases: [old], keepsFolder: { _ in true }).scan()
        XCTAssertEqual(sessions.map(\.title), ["old one"])
        XCTAssertEqual(sessions.first?.projectPath, "/Users/t/q", "the first local folder, past a non-file URI")
        XCTAssertEqual(sessions.first?.createdAt, sessions.first?.modifiedAt, "no prompt time: the last change")
    }

    func testLastConversationPerFolder() throws {
        let cache = root.appendingPathComponent("last_conversations.json")
        try Data(#"{"/Users/t/p": "0be8de45-69fe-48db-9f4c-2c4b81320fa9"}"#.utf8).write(to: cache)
        XCTAssertEqual(AntigravitySessionSource.lastConversations(cache: cache), ["/Users/t/p": cli])
        XCTAssertEqual(AntigravitySessionSource.lastConversations(cache: root.appendingPathComponent("none.json")), [:])
    }

    func testResumeCommandsAndRunningConversation() {
        XCTAssertEqual(AgentKind.classify(commandLine: ["/Users/t/.local/bin/agy"]), .antigravity)
        XCTAssertEqual(AgentKind.antigravity.sessionID(fromCommandLine: ["agy", "--conversation", cli]), cli)
        XCTAssertEqual(AgentKind.antigravity.sessionID(fromCommandLine: ["agy", "-r", cli]), cli)
        XCTAssertNil(AgentKind.antigravity.sessionID(fromCommandLine: ["agy", "-c"]))
        XCTAssertEqual(AgentKind.antigravity.continueCommand, "agy --continue")
        XCTAssertEqual(AgentKind.antigravity.pickerCommand, "agy")
    }
}
