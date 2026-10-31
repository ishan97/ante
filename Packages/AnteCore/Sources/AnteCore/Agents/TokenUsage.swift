// Packages/AnteCore/Sources/AnteCore/Agents/TokenUsage.swift
import Foundation

/// Tokens one model call (or one Codex turn) used, split the way every provider bills them.
/// `input` is fresh input only: cache reads and writes are counted on their own.
public struct TokenCount: Equatable, Hashable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static let zero = TokenCount()

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
    }

    public static func += (a: inout TokenCount, b: TokenCount) { a = a + b }

    /// Reads a count from a JSON value. Anything that is not a sane non-negative whole number
    /// counts as zero, so a malformed or hostile log can never overflow a total.
    static func field(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return Int(min(double, Double(Self.ceiling)))
    }

    /// No single record can claim more than this (no API call comes near it), so even billions
    /// of planted records cannot overflow an Int total.
    static let ceiling = 1_000_000_000
}

/// One usage entry from an agent's own logs.
public struct TokenRecord: Equatable, Sendable {
    public let at: Date
    public let agent: AgentKind
    public let model: String
    public let count: TokenCount
    /// Identifies the same API response written twice (streamed chunks, resumed or forked
    /// transcripts) so it is counted once. Nil when the format has no such id.
    public let key: String?

    public init(at: Date, agent: AgentKind, model: String, count: TokenCount, key: String? = nil) {
        self.at = at
        self.agent = agent
        self.model = model
        self.count = count
        self.key = key
    }
}

/// What the toolbar's token chip and its popover show: totals over a few rolling windows, each
/// split by agent, by model and by kind of token.
public struct TokenUsageReport: Equatable, Sendable {
    public enum Window: String, CaseIterable, Identifiable, Sendable {
        case day, week, month, twoMonths, quarter, halfYear, year

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .day: return "24 hours"
            case .week: return "7 days"
            case .month: return "30 days"
            case .twoMonths: return "60 days"
            case .quarter: return "90 days"
            case .halfYear: return "6 months"
            case .year: return "1 year"
            }
        }

        /// Where the window starts: rolling, ending now.
        public func start(before now: Date, calendar: Calendar = .current) -> Date {
            let ago: (Calendar.Component, Int)
            switch self {
            case .day: return now.addingTimeInterval(-24 * 3600)
            case .week: ago = (.day, 7)
            case .month: ago = (.day, 30)
            case .twoMonths: ago = (.day, 60)
            case .quarter: ago = (.day, 90)
            case .halfYear: ago = (.month, 6)
            case .year: ago = (.year, 1)
            }
            return calendar.date(byAdding: ago.0, value: -ago.1, to: now) ?? now
        }
    }

    public struct Share: Equatable, Sendable, Identifiable {
        public let name: String
        public let tokens: Int
        public var id: String { name }
    }

    public struct AgentShare: Equatable, Sendable, Identifiable {
        public let agent: AgentKind
        public let tokens: Int
        public var id: AgentKind { agent }

        public init(agent: AgentKind, tokens: Int) {
            self.agent = agent
            self.tokens = tokens
        }
    }

    public struct Slice: Equatable, Sendable, Identifiable {
        public let window: Window
        public let count: TokenCount
        /// Largest first.
        public let byAgent: [AgentShare]
        /// Largest first; every model, the view decides how many to show.
        public let byModel: [Share]
        public var id: Window { window }
        public var total: Int { count.total }
    }

    /// One per window, in `Window.allCases` order.
    public let slices: [Slice]
    public let generatedAt: Date

    public func slice(_ window: Window) -> Slice {
        slices.first { $0.window == window } ?? Slice(window: window, count: .zero, byAgent: [], byModel: [])
    }

    /// True when no agent has logged a single token in the last year.
    public var isEmpty: Bool { slice(.year).total == 0 }

    public static func build(records: [TokenRecord], now: Date = Date(), calendar: Calendar = .current) -> TokenUsageReport {
        // The same response can sit in several files; the first copy wins.
        var seen = Set<String>()
        var unique: [TokenRecord] = []
        unique.reserveCapacity(records.count)
        for record in records where record.at <= now {
            if let key = record.key, !seen.insert(key).inserted { continue }
            unique.append(record)
        }
        let slices = Window.allCases.map { window -> Slice in
            let start = window.start(before: now, calendar: calendar)
            var count = TokenCount.zero
            var agents: [AgentKind: Int] = [:]
            var models: [String: Int] = [:]
            for record in unique where record.at > start {
                count += record.count
                agents[record.agent, default: 0] += record.count.total
                models[record.model.isEmpty ? "unknown" : record.model, default: 0] += record.count.total
            }
            let byAgent = agents.filter { $0.value > 0 }.map { AgentShare(agent: $0.key, tokens: $0.value) }
            let byModel = models.filter { $0.value > 0 }.map { Share(name: $0.key, tokens: $0.value) }
            // Largest first; ties by name so the order never flickers between refreshes.
            return Slice(window: window, count: count,
                         byAgent: byAgent.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.agent.rawValue < $1.agent.rawValue },
                         byModel: byModel.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.name < $1.name })
        }
        return TokenUsageReport(slices: slices, generatedAt: now)
    }
}
