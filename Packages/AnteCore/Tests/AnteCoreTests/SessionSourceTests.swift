// Packages/AnteCore/Tests/AnteCoreTests/SessionSourceTests.swift
import XCTest
@testable import AnteCore

final class SessionSourceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ lines: [String], to path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        return url
    }

    func testClaudeScanFindsRealPromptSkipsMetaAndToolResultsUsesSummaryAndIndex() throws {
        let projects = root.appendingPathComponent("claude")
        let a = UUID().uuidString, b = UUID().uuidString
        _ = try write([
            #"{"type":"user","isMeta":true,"cwd":"/Users/t/proj","sessionId":"\#(a)","timestamp":"2026-08-16T10:16:20.417Z","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"user","cwd":"/Users/t/proj","sessionId":"\#(a)","timestamp":"2026-08-16T10:16:21.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}"#,
            #"{"type":"user","cwd":"/Users/t/proj","sessionId":"\#(a)","timestamp":"2026-08-16T10:16:22.000Z","message":{"role":"user","content":"Fix the   login\nbug please"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure"}]}}"#,
        ], to: "claude/-Users-t-proj/\(a).jsonl")
        _ = try write([
            #"{"type":"summary","summary":"Login bug fixed","leafUuid":"x"}"#,
            #"{"type":"user","cwd":"/Users/t/other","sessionId":"\#(b)","timestamp":"2026-08-17T10:00:00.000Z","message":{"role":"user","content":"hello there"}}"#,
        ], to: "claude/-Users-t-other/\(b).jsonl")
        _ = try write(["not json at all"], to: "claude/-Users-t-other/broken.jsonl")
        _ = try write([#"{"entries":[{"sessionId":"\#(a)","summary":"Index title wins","firstPrompt":"Fix the login bug please"}],"version":1}"#],
                      to: "claude/-Users-t-proj/sessions-index.json")
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("memory"), withIntermediateDirectories: true)

        let sessions = ClaudeSessionSource(root: projects).scan()
        XCTAssertEqual(sessions.count, 2, "\(sessions)")
        let first = try XCTUnwrap(sessions.first { $0.id == a })
        XCTAssertEqual(first.title, "Index title wins", "index summary beats the file's first prompt")
        XCTAssertEqual(first.projectPath, "/Users/t/proj")
        XCTAssertEqual(first.agent, .claude)
        XCTAssertEqual(first.resumeCommand, "claude --resume \(a)")
        XCTAssertEqual(first.createdAt, ISO8601DateFormatter.anteFractional.date(from: "2026-08-16T10:16:22.000Z"))
        let second = try XCTUnwrap(sessions.first { $0.id == b })
        XCTAssertEqual(second.title, "Login bug fixed", "summary record beats the first prompt")
        XCTAssertEqual(sessions.first?.modifiedAt ?? .distantPast, sessions.map(\.modifiedAt).max(), "newest first")
    }

    func testClaudeTitleFallsBackToFirstPromptCleanedAndTruncated() throws {
        let id = UUID().uuidString
        let long = String(repeating: "word ", count: 60)
        _ = try write([#"{"type":"user","cwd":"/p","sessionId":"\#(id)","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"\#(long)"}}"#],
                      to: "claude/-p/\(id).jsonl")
        let s = try XCTUnwrap(ClaudeSessionSource(root: root.appendingPathComponent("claude")).scan().first)
        XCTAssertEqual(s.title.count, 118)
        XCTAssertTrue(s.title.hasSuffix("…"))
    }

    func testCodexScanReadsMetaAndFirstUserMessage() throws {
        _ = try write([
            #"{"timestamp":"2026-06-14T16:16:55.154Z","type":"session_meta","payload":{"id":"019ec6eb-fa35-7a90-885d-23d8ae36f542","timestamp":"2026-06-14T16:16:54.325Z","cwd":"/Users/t/ws","source":"cli"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"<environment_context>x</environment_context>"}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"Refactor the parser"}}"#,
        ], to: "codex/2026/06/14/rollout-2026-06-14T18-16-54-019ec6eb.jsonl")
        let sessions = CodexSessionSource(root: root.appendingPathComponent("codex")).scan()
        XCTAssertEqual(sessions.count, 1)
        let s = sessions[0]
        XCTAssertEqual(s.id, "019ec6eb-fa35-7a90-885d-23d8ae36f542")
        XCTAssertEqual(s.title, "Refactor the parser")
        XCTAssertEqual(s.projectPath, "/Users/t/ws")
        XCTAssertEqual(s.detail, "cli")
        XCTAssertEqual(s.resumeCommand, "codex resume 019ec6eb-fa35-7a90-885d-23d8ae36f542")
    }

    func testScannersReadOnlyTheHeadOfHugeFiles() throws {
        let id = UUID().uuidString
        var lines = [#"{"type":"user","cwd":"/p","sessionId":"\#(id)","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"early"}}"#]
        lines += (0..<3000).map { _ in #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(String(repeating: "x", count: 100))"}]}}"# }
        lines.append(#"{"type":"summary","summary":"late summary beyond the cap"}"#)
        _ = try write(lines, to: "claude/-p/\(id).jsonl")
        let s = try XCTUnwrap(ClaudeSessionSource(root: root.appendingPathComponent("claude")).scan().first)
        XCTAssertEqual(s.title, "early", "a summary past the 64 KB head is not read")
    }

    func testClaudeSkipsSubagentTranscriptsAndSidechains() throws {
        let id = UUID().uuidString, side = UUID().uuidString
        _ = try write([#"{"type":"user","cwd":"/p","sessionId":"\#(id)","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"real one"}}"#],
                      to: "claude/-p/\(id).jsonl")
        _ = try write([#"{"type":"user","isSidechain":true,"cwd":"/p","sessionId":"\#(side)","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"fork"}}"#],
                      to: "claude/-p/\(side).jsonl")
        _ = try write([#"{"type":"user","cwd":"/p","sessionId":"x","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"subagent"}}"#],
                      to: "claude/-p/agent-abc123.jsonl")
        let sessions = ClaudeSessionSource(root: root.appendingPathComponent("claude")).scan()
        XCTAssertEqual(sessions.map(\.title), ["real one"])
    }

    func testCodexScansArchivedSessionsWithoutDuplicates() throws {
        let line = #"{"timestamp":"2026-06-14T16:16:55.154Z","type":"session_meta","payload":{"id":"019ec6eb-fa35-7a90-885d-23d8ae36f542","timestamp":"2026-06-14T16:16:54.325Z","cwd":"/Users/t/ws","source":"cli"}}"#
        _ = try write([line], to: "codex/2026/06/14/rollout-a.jsonl")
        _ = try write([line], to: "codex-archived/2026/06/14/rollout-a.jsonl")
        _ = try write([line.replacingOccurrences(of: "019ec6eb-fa35-7a90-885d-23d8ae36f542", with: "019ec6eb-0000-7a90-885d-23d8ae36f542")], to: "codex-archived/2026/05/01/rollout-b.jsonl")
        let sessions = CodexSessionSource(root: root.appendingPathComponent("codex"), archivedRoot: root.appendingPathComponent("codex-archived")).scan()
        XCTAssertEqual(sessions.count, 2, "archived sessions are listed once each")
    }
}

extension SessionSourceTests {
    func testTitlesLoseControlCharactersAndCollapseWhitespace() {
        XCTAssertEqual(ClaudeSessionSource.clean("Fix\u{1B}[31m the  \n login\u{07} bug"), "Fix[31m the login bug")
        XCTAssertEqual(ClaudeSessionSource.clean(String(repeating: "a", count: 200)).count, 118)
    }
}
