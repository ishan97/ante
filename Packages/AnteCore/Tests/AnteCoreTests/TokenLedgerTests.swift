import XCTest
import SQLite3
@testable import AnteCore

final class TokenLedgerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-tokens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var sources: TokenLedger.Sources {
        TokenLedger.Sources(claudeProjects: root.appendingPathComponent("claude"), codexRoots: [root.appendingPathComponent("codex")],
                            openCodeDatabase: root.appendingPathComponent("opencode.db"), piSessions: root.appendingPathComponent("pi"),
                            geminiTmp: root.appendingPathComponent("gemini"))
    }

    private func write(_ relative: String, _ lines: [String]) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ url: URL, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func claudeLine(id: String, request: String = "req_1", at: Date, input: Int = 10, output: Int = 5, read: Int = 100, write: Int = 20, model: String = "claude-opus-5-5") -> String {
        #"{"type":"assistant","timestamp":"\#(iso(at))","requestId":"\#(request)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":\#(read),"cache_creation_input_tokens":\#(write)}}}"#
    }

    func testClaudeCountsEveryKindAndDropsDuplicateResponses() async throws {
        let now = Date()
        _ = try write("claude/proj/a.jsonl", [
            #"{"type":"user","message":{"content":"hi, my usage is fine"}}"#,
            claudeLine(id: "msg_1", at: now.addingTimeInterval(-60)),
            claudeLine(id: "msg_1", at: now.addingTimeInterval(-60)),                       // streamed twice
            claudeLine(id: "msg_2", at: now.addingTimeInterval(-3 * 86400), model: "claude-sonnet-5-5"),
        ])
        // A resumed session copies an earlier response into a new file.
        _ = try write("claude/proj/b/subagents/agent-x.jsonl", [claudeLine(id: "msg_1", at: now.addingTimeInterval(-60))])
        let report = await TokenLedger(sources: sources).report(now: now)
        let day = report.slice(.day)
        XCTAssertEqual(day.count, TokenCount(input: 10, output: 5, cacheRead: 100, cacheWrite: 20))
        XCTAssertEqual(day.total, 135)
        XCTAssertEqual(report.slice(.week).total, 270)
        XCTAssertEqual(report.slice(.week).byModel.map(\.name), ["claude-opus-5-5", "claude-sonnet-5-5"])
        XCTAssertEqual(report.slice(.week).byAgent.map(\.agent), [.claude])
    }

    func testCodexCountsGrowthOfTheRunningTotal() async throws {
        let now = Date()
        func tokenCount(_ input: Int, _ cached: Int, _ output: Int, last: (Int, Int, Int)? = nil, at: Date) -> String {
            let l = last ?? (input, cached, output)
            return #"{"timestamp":"\#(iso(at))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":\#(l.0),"cached_input_tokens":\#(l.1),"output_tokens":\#(l.2)}}}}"#
        }
        let t = now.addingTimeInterval(-600)
        _ = try write("codex/2026/10/30/rollout-1.jsonl", [
            #"{"timestamp":"\#(iso(t))","type":"session_meta","payload":{"id":"s1","cwd":"/tmp"}}"#,
            #"{"timestamp":"\#(iso(t))","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"\#(iso(t))","type":"event_msg","payload":{"type":"token_count","info":null}}"#,   // rate limits only
            tokenCount(1000, 200, 50, at: t),
            tokenCount(1000, 200, 50, at: t),                     // repeated, nothing new
            tokenCount(3000, 1200, 150, at: t),
        ])
        let report = await TokenLedger(sources: sources).report(now: now)
        // 3000 input of which 1200 cached, plus 150 output.
        XCTAssertEqual(report.slice(.day).count, TokenCount(input: 1800, output: 150, cacheRead: 1200))
        XCTAssertEqual(report.slice(.day).byModel.map(\.name), ["gpt-5-codex"])
        XCTAssertEqual(report.slice(.day).byAgent.map(\.agent), [.codex])
    }

    func testCodexAppendsUseTheRememberedRunningTotalAndModel() async throws {
        let now = Date()
        let t = now.addingTimeInterval(-600)
        func tokenCount(_ input: Int, _ cached: Int, _ output: Int, last: (Int, Int, Int)) -> String {
            #"{"timestamp":"\#(iso(t))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)},"last_token_usage":{"input_tokens":\#(last.0),"cached_input_tokens":\#(last.1),"output_tokens":\#(last.2)}}}}"#
        }
        let file = try write("codex/r.jsonl", [
            #"{"timestamp":"\#(iso(t))","type":"turn_context","payload":{"model":"gpt-a"}}"#,
            tokenCount(100, 0, 10, last: (100, 0, 10)),
        ])
        let ledger = TokenLedger(sources: sources)
        var day = await ledger.report(now: now).slice(.day)
        XCTAssertEqual(day.total, 110)
        // Appended later: a new model, then growth of the same running total.
        try append(file, #"{"timestamp":"\#(iso(t))","type":"turn_context","payload":{"model":"gpt-b"}}"# + "\n" + tokenCount(300, 50, 30, last: (200, 50, 20)) + "\n")
        day = await ledger.report(now: now).slice(.day)
        XCTAssertEqual(day.total, 330)
        XCTAssertEqual(day.byModel.first { $0.name == "gpt-b" }?.tokens, 220, "only the growth, under the new model")
        // The running total goes backwards (a new context): the turn's own figure counts.
        try append(file, tokenCount(40, 0, 5, last: (40, 0, 5)) + "\n")
        day = await ledger.report(now: now).slice(.day)
        XCTAssertEqual(day.total, 375)
    }

    func testTruncatedInPlaceIsReadAgainFromTheTop() async throws {
        let now = Date()
        let file = try write("claude/p/t.jsonl", [claudeLine(id: "a", at: now.addingTimeInterval(-10)), claudeLine(id: "b", at: now.addingTimeInterval(-10))])
        let ledger = TokenLedger(sources: sources)
        var total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 270)
        // Same inode, shorter content.
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data((claudeLine(id: "c", at: now.addingTimeInterval(-5), input: 3, output: 0, read: 0, write: 0) + "\n").utf8))
        try handle.close()
        total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 3)
    }

    func testGrowingFilesAreReadIncrementallyAndHalfWrittenLinesWait() async throws {
        let now = Date()
        let file = try write("claude/p/s.jsonl", [claudeLine(id: "m1", at: now.addingTimeInterval(-10))])
        let ledger = TokenLedger(sources: sources)
        var total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 135)
        // The agent is mid-write: the line has no newline yet.
        let next = claudeLine(id: "m2", at: now.addingTimeInterval(-5), input: 1, output: 1, read: 0, write: 0)
        try append(file, String(next.prefix(40)))
        total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 135)
        try append(file, String(next.dropFirst(40)) + "\n")
        total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 137)
        // Rewritten from scratch (smaller): read again from the top.
        _ = try write("claude/p/s.jsonl", [claudeLine(id: "m3", at: now.addingTimeInterval(-1), input: 7, output: 0, read: 0, write: 0)])
        total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 7)
        try FileManager.default.removeItem(at: file)
        total = await ledger.report(now: now).slice(.day).total
        XCTAssertEqual(total, 0)
    }

    func testPiAndGemini() async throws {
        let now = Date()
        let at = iso(now.addingTimeInterval(-100))
        _ = try write("pi/--tmp--/s.jsonl", [
            #"{"type":"session","id":"p1","cwd":"/tmp","timestamp":"\#(at)"}"#,
            #"{"type":"message","id":"e1","timestamp":"\#(at)","message":{"role":"user","content":"usage?"}}"#,
            #"{"type":"message","id":"e2","timestamp":"\#(at)","message":{"role":"assistant","model":"gpt-5","usage":{"input":40,"output":10,"cacheRead":5,"cacheWrite":1,"totalTokens":56}}}"#,
        ])
        let gemini = #"{"sessionId":"g1","messages":[{"id":"u","type":"user","timestamp":"\#(at)","content":"x"},{"id":"a","type":"gemini","timestamp":"\#(at)","model":"gemini-3-pro","tokens":{"input":100,"output":20,"cached":30,"thoughts":5,"tool":2,"total":127}}]}"#
        _ = try write("gemini/hash/chats/session-2026-10-30T10-00-g1.json", [gemini])
        _ = try write("gemini/hash/logs.json", [#"{"messages":[{"tokens":{"input":999}}]}"#])   // not a chat
        let report = await TokenLedger(sources: sources).report(now: now)
        let day = report.slice(.day)
        XCTAssertEqual(Set(day.byAgent.map(\.agent)), [.pi, .gemini])
        XCTAssertEqual(day.byAgent.first { $0.agent == .pi }?.tokens, 56)
        XCTAssertEqual(day.byAgent.first { $0.agent == .gemini }?.tokens, 127)
    }

    func testOpenCodeDatabase() async throws {
        let db = root.appendingPathComponent("opencode.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(db.path, &handle), SQLITE_OK)
        let now = Date()
        let recent = Int64(now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        let old = Int64(now.addingTimeInterval(-400 * 86400).timeIntervalSince1970 * 1000)
        let sql = """
            CREATE TABLE message (id text PRIMARY KEY, session_id text, time_created integer, time_updated integer, data text);
            INSERT INTO message VALUES ('1', 's', \(recent), \(recent), '{"role":"assistant","modelID":"big-pickle","tokens":{"input":100,"output":10,"reasoning":5,"cache":{"read":50,"write":2}}}');
            INSERT INTO message VALUES ('2', 's', \(recent), \(recent), '{"role":"user","tokens":{"input":999}}');
            INSERT INTO message VALUES ('3', 's', \(recent), \(recent), 'not json');
            INSERT INTO message VALUES ('4', 's', \(old), \(old), '{"role":"assistant","tokens":{"input":999}}');
            """
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let report = await TokenLedger(sources: sources).report(now: now)
        XCTAssertEqual(report.slice(.year).count, TokenCount(input: 100, output: 15, cacheRead: 50, cacheWrite: 2))
        XCTAssertEqual(report.slice(.year).byModel.map(\.name), ["big-pickle"])
    }

    func testHostileNumbersCountAsZero() {
        XCTAssertEqual(TokenCount.field(-5), 0)
        XCTAssertEqual(TokenCount.field("12"), 0)
        XCTAssertEqual(TokenCount.field(Double.infinity), 0)
        XCTAssertEqual(TokenCount.field(1e300), TokenCount.ceiling)
        XCTAssertEqual(TokenCount.field(42), 42)
    }

    func testWindowsAreRollingAndNested() {
        let now = Date()
        let records = [1.0, 5, 20, 45, 80, 150, 300, 400].map { days in
            TokenRecord(at: now.addingTimeInterval(-days * 86400 + 60), agent: .claude, model: "m", count: TokenCount(output: 1))
        } + [TokenRecord(at: now.addingTimeInterval(3600), agent: .claude, model: "m", count: TokenCount(output: 1000))]   // future
        let report = TokenUsageReport.build(records: records, now: now)
        XCTAssertEqual(report.slices.map(\.total), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(TokenUsageReport.build(records: [], now: now).isEmpty)
    }

    func testMissingSourcesGiveAnEmptyReport() async {
        let report = await TokenLedger(sources: sources).report()
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.slices.count, TokenUsageReport.Window.allCases.count)
    }
}
