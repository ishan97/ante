// Packages/AnteCore/Sources/AnteCore/Agents/ActivityStats.swift
import Foundation

/// One prompt sent to an agent: when, in which session, to whom.
public struct ActivityEvent: Equatable, Sendable {
    public let at: Date
    public let sessionID: String
    public let agent: AgentKind

    public init(at: Date, sessionID: String, agent: AgentKind) {
        self.at = at
        self.sessionID = sessionID
        self.agent = agent
    }
}

/// What the Activity strip on the Sessions board shows: a day-by-day count of prompts over the
/// last year, and a few numbers to be proud of.
public struct ActivityStats: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: Date        // start of day
        public let prompts: Int
        public let sessions: Int
    }

    /// Oldest first, one entry per calendar day, zero days included, ending today.
    public let days: [Day]
    public let totalPrompts: Int
    public let totalSessions: Int
    public let activeDays: Int
    /// Consecutive active days ending today (or yesterday, if today is still quiet).
    public let currentStreak: Int
    public let longestStreak: Int
    /// Prompts per hour of day, 0–23, local time.
    public let byHour: [Int]
    public var busiestHour: Int? { byHour.max().flatMap { $0 > 0 ? byHour.firstIndex(of: $0) : nil } }
    public var busiestDay: Day? { days.max { $0.prompts < $1.prompts }.flatMap { $0.prompts > 0 ? $0 : nil } }

    public static func build(events: [ActivityEvent], days span: Int = 365, now: Date = Date(),
                             calendar: Calendar = .current) -> ActivityStats {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(span - 1), to: today) else {
            return ActivityStats(days: [], totalPrompts: 0, totalSessions: 0, activeDays: 0, currentStreak: 0, longestStreak: 0, byHour: Array(repeating: 0, count: 24))
        }
        var prompts: [Date: Int] = [:]
        var sessions: [Date: Set<String>] = [:]
        var allSessions = Set<String>()
        var byHour = Array(repeating: 0, count: 24)
        for event in events where event.at >= start && event.at <= now {
            let day = calendar.startOfDay(for: event.at)
            prompts[day, default: 0] += 1
            sessions[day, default: []].insert(event.sessionID)
            allSessions.insert(event.sessionID)
            byHour[calendar.component(.hour, from: event.at)] += 1
        }
        var out: [Day] = []
        var cursor = start
        var streak = 0, longest = 0
        while cursor <= today {
            let count = prompts[cursor] ?? 0
            out.append(Day(date: cursor, prompts: count, sessions: sessions[cursor]?.count ?? 0))
            streak = count > 0 ? streak + 1 : 0
            longest = max(longest, streak)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        // Today counts toward the streak only once you have prompted; a quiet morning does not break it.
        var current = 0
        for day in out.reversed() {
            if day.prompts > 0 { current += 1 }
            else if day.date == today && current == 0 { continue }
            else { break }
        }
        return ActivityStats(days: out, totalPrompts: out.reduce(0) { $0 + $1.prompts }, totalSessions: allSessions.count,
                             activeDays: out.filter { $0.prompts > 0 }.count, currentStreak: current, longestStreak: longest, byHour: byHour)
    }
}

/// Claude Code appends one line per prompt to `~/.claude/history.jsonl` — and never prunes it,
/// unlike transcripts — so a year of activity is there even after old sessions are cleaned up.
public struct ClaudeHistorySource: Sendable {
    public let file: URL

    public init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")) {
        self.file = file
    }

    public func events() -> [ActivityEvent] {
        return JSONLines.parse(HistoryTail.read(file)).compactMap { record in
            guard let ms = record["timestamp"] as? Double else { return nil }
            return ActivityEvent(at: Date(timeIntervalSince1970: ms / 1000), sessionID: record["sessionId"] as? String ?? "", agent: .claude)
        }
    }
}

/// Codex keeps `~/.codex/history.jsonl` with `ts` (seconds) and `session_id`.
public struct CodexHistorySource: Sendable {
    public let file: URL

    public init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/history.jsonl")) {
        self.file = file
    }

    public func events() -> [ActivityEvent] {
        return JSONLines.parse(HistoryTail.read(file)).compactMap { record in
            guard let ts = record["ts"] as? Double else { return nil }
            return ActivityEvent(at: Date(timeIntervalSince1970: ts), sessionID: record["session_id"] as? String ?? "", agent: .codex)
        }
    }
}

/// Reads at most the last `limit` bytes of an append-only log, starting at a line boundary, so a
/// history file that grew for years cannot exhaust memory.
enum HistoryTail {
    static let limit: UInt64 = 16 * 1024 * 1024

    static func read(_ url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > limit ? size - limit : 0
        try? handle.seek(toOffset: start)
        var data = (try? handle.readToEnd()) ?? Data()
        if start > 0, let newline = data.firstIndex(of: 0x0A) { data = data[(newline + 1)...] }
        return Data(data)
    }
}
