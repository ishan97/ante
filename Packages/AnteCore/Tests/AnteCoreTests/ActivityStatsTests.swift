// Packages/AnteCore/Tests/AnteCoreTests/ActivityStatsTests.swift
import XCTest
@testable import AnteCore

final class ActivityStatsTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testCountsDaysSessionsStreaksAndHours() {
        let now = date("2026-09-17T15:00:00Z")
        let events = [
            ActivityEvent(at: date("2026-09-17T09:10:00Z"), sessionID: "a", agent: .claude),
            ActivityEvent(at: date("2026-09-17T09:40:00Z"), sessionID: "a", agent: .claude),
            ActivityEvent(at: date("2026-09-16T22:00:00Z"), sessionID: "b", agent: .claude),
            ActivityEvent(at: date("2026-09-15T09:00:00Z"), sessionID: "c", agent: .codex),
            ActivityEvent(at: date("2026-09-10T09:00:00Z"), sessionID: "d", agent: .claude),
            ActivityEvent(at: date("2026-09-09T09:00:00Z"), sessionID: "d", agent: .claude),
            ActivityEvent(at: date("2026-09-08T09:00:00Z"), sessionID: "e", agent: .claude),
            ActivityEvent(at: date("2026-09-07T09:00:00Z"), sessionID: "f", agent: .claude),
            ActivityEvent(at: date("2025-01-01T09:00:00Z"), sessionID: "old", agent: .claude),   // outside the year
            ActivityEvent(at: date("2026-09-18T09:00:00Z"), sessionID: "future", agent: .claude),
        ]
        let stats = ActivityStats.build(events: events, days: 30, now: now, calendar: calendar)
        XCTAssertEqual(stats.days.count, 30)
        XCTAssertEqual(stats.days.last?.date, date("2026-09-17T00:00:00Z"))
        XCTAssertEqual(stats.days.last?.prompts, 2)
        XCTAssertEqual(stats.days.last?.sessions, 1)
        XCTAssertEqual(stats.totalPrompts, 8, "old and future events are ignored")
        XCTAssertEqual(stats.totalSessions, 6)
        XCTAssertEqual(stats.activeDays, 7)
        XCTAssertEqual(stats.currentStreak, 3, "15, 16, 17")
        XCTAssertEqual(stats.longestStreak, 4, "7, 8, 9, 10")
        XCTAssertEqual(stats.busiestHour, 9)
        XCTAssertEqual(stats.busiestDay?.date, date("2026-09-17T00:00:00Z"))
    }

    func testQuietTodayKeepsYesterdaysStreak() {
        let now = date("2026-09-17T08:00:00Z")
        let events = ["2026-09-16", "2026-09-15"].map { ActivityEvent(at: date("\($0)T12:00:00Z"), sessionID: $0, agent: .claude) }
        XCTAssertEqual(ActivityStats.build(events: events, days: 10, now: now, calendar: calendar).currentStreak, 2)
    }

    func testOnlyTheTailOfAHugeHistoryIsRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-tail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("history.jsonl")
        let line = "{\"timestamp\":1767802771166,\"sessionId\":\"s\",\"display\":\"" + String(repeating: "x", count: 1000) + "\"}\n"
        let handle = FileHandle(forWritingAtPath: { FileManager.default.createFile(atPath: file.path, contents: nil); return file.path }())!
        for _ in 0..<20_000 { try handle.write(contentsOf: Data(line.utf8)) }   // ~20 MB
        try handle.close()
        let events = ClaudeHistorySource(file: file).events()
        XCTAssertGreaterThan(events.count, 10_000)
        XCTAssertLessThan(events.count, 20_000, "the head of the file is skipped")
    }

    func testClaudeAndCodexHistoryFilesParse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-act-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let claude = root.appendingPathComponent("history.jsonl")
        try Data("""
        {"display":"hi","pastedContents":{},"timestamp":1767802771166,"project":"/p","sessionId":"s1"}
        not json
        {"display":"again","timestamp":1767803092434,"project":"/p","sessionId":"s1"}
        """.utf8).write(to: claude)
        let codex = root.appendingPathComponent("codex.jsonl")
        try Data(#"{"session_id":"c1","ts":1767802771,"text":"x"}"#.utf8).write(to: codex)
        let c = ClaudeHistorySource(file: claude).events()
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c.first?.sessionID, "s1")
        XCTAssertEqual(c.first?.at.timeIntervalSince1970 ?? 0, 1767802771.166, accuracy: 0.001)
        let x = CodexHistorySource(file: codex).events()
        XCTAssertEqual(x.first?.agent, .codex)
        XCTAssertEqual(x.first?.at.timeIntervalSince1970, 1767802771)
        XCTAssertTrue(ClaudeHistorySource(file: root.appendingPathComponent("missing.jsonl")).events().isEmpty)
    }
}
