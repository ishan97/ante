// Packages/AnteUI/Sources/AnteUI/Sessions/BoardState.swift
import Foundation
import AnteCore

public enum BoardColumn: String, CaseIterable, Sendable { case working, waiting, idle
    public var title: String { switch self { case .working: return "Working"; case .waiting: return "Waiting for you"; case .idle: return "Idle" } }
}

public enum CardState: Equatable, Sendable {
    case working
    case waitingDefinite(String)
    case waitingProbable
    case idle
    public var column: BoardColumn { switch self { case .working: return .working; case .waitingDefinite, .waitingProbable: return .waiting; case .idle: return .idle } }
}

public enum BoardRules {
    /// Sources, most trusted first:
    /// 1. `title` — the agent's own status line (Claude Code spins `◐` while busy, `✳` when it
    ///    waits). Instant, and a repaint cannot fake it.
    /// 2. `notice` — the program's own OSC 9 notification ("Claude needs your permission"), and
    ///    `hook` — the latest hook meaning for this pane's cwd. Both give the *reason* and stick
    ///    until the user answers (`inputAt` newer): output alone never overrides them, because a
    ///    waiting agent still repaints on resize or focus.
    /// 3. Quiet time, for agents that tell us nothing.
    public static func state(agent: AgentKind, commandRunning: Bool, lastOutputAt: Date, inputAt: Date? = nil,
                             title: AgentTitle? = nil, notice: String? = nil, noticeAt: Date? = nil,
                             hook: HookEvent.Meaning?, hookAt: Date?, now: Date, quietSeconds: Double) -> CardState {
        if agent == .shell, !commandRunning { return .idle }
        let answered = inputAt ?? .distantPast
        let hookIsCurrent = hookAt.map { answered <= $0 } ?? false
        let noticeIsCurrent = noticeAt.map { answered <= $0 } ?? false
        var reason: String?
        if noticeIsCurrent, let notice { reason = notice }
        if hookIsCurrent, case let .waiting(text)? = hook, hookAt! >= (noticeAt ?? .distantPast) { reason = text }
        if let title {
            switch title.state {
            case .busy: return .working
            case .idle: return .waitingDefinite(reason ?? "waiting for input")
            }
        }
        if let reason { return .waitingDefinite(reason) }
        if let hook, hookIsCurrent, case .working = hook { return .working }
        if agent.isAgent, now.timeIntervalSince(lastOutputAt) >= quietSeconds { return .waitingProbable }
        return .working
    }
}
