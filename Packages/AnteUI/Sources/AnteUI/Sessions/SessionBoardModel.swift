// Packages/AnteUI/Sources/AnteUI/Sessions/SessionBoardModel.swift
import Foundation
import Observation
import AppKit
import AnteCore
import AnteTerm

/// What the Sessions view shows: one card per live pane, sorted into columns, plus the history
/// list. Cards are recomputed once a second (cheap: a dozen panes at most) and whenever a hook
/// event arrives.
@MainActor
@Observable
public final class SessionBoardModel {
    public struct Card: Identifiable, Equatable, Sendable {
        public let id: PaneID
        public let sessionID: SessionID
        public let sessionName: String
        public let projectName: String
        public let agent: AgentKind
        public let subtitle: String
        public let state: CardState
        public let since: Date
    }

    public private(set) var cards: [Card] = []
    public private(set) var history: [PastSession] = []
    public private(set) var isLoadingHistory = false
    /// Claude Code's `cleanupPeriodDays`, read with the history so the list can say why it ends.
    public private(set) var claudeRetentionDays = ClaudeHookInstaller.defaultRetentionDays
    /// A year of prompts per day from the agents' own history files.
    public private(set) var activity: ActivityStats?
    public var query = ""
    public var agentFilter: AgentKind?

    private unowned let runtime: WorkspaceRuntime
    private var hookSignals: [String: (meaning: HookEvent.Meaning, at: Date)] = [:]
    private var columnSince: [PaneID: (column: BoardColumn, at: Date)] = [:]
    private var timer: Timer?
    /// Delivers a "waiting for you" notification (macOS notification + the configured sound);
    /// tests replace it with a recorder.
    public var deliverWaiting: (Card, String) -> Void = { _, _ in }
    /// The Dock badge; replaceable so tests never touch NSApp.
    public var setBadge: (Int) -> Void = { count in NSApp?.dockTile.badgeLabel = count > 0 ? String(count) : nil }
    /// Whether the user is looking at Ante. The workspace window is a non-activating panel, so
    /// clicking into it makes it key without making the app active; either counts.
    public var isInFront: () -> Bool = { (NSApp?.isActive ?? false) || NSApp?.keyWindow != nil }

    init(runtime: WorkspaceRuntime) {
        self.runtime = runtime
        deliverWaiting = { [unowned runtime] card, reason in
            WaitingNotifier.post(card: card, reason: reason, sound: runtime.config.agents.notifySound)
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Hooks

    public func ingest(_ events: [HookEvent]) {
        for event in events {
            guard let cwd = event.cwd, event.meaning != .other else { continue }
            hookSignals[Self.normalize(cwd)] = (event.meaning, event.at)
        }
        refresh()
    }

    // MARK: - Cards

    public func refresh() {
        let now = Date()
        let quiet = runtime.config.agents.quietSeconds
        var next: [Card] = []
        for session in runtime.store.allVisibleSessions {
            guard let layout = runtime.existingLayout(for: session.id) else { continue }
            let project = runtime.store.state.projects.first { $0.id == session.projectID }
            for pane in layout.paneIDs {
                let controller = runtime.controller(for: pane)
                guard controller.state == .running else { continue }
                let cwd = controller.currentDirectory.map { Self.normalize($0.path) }
                let signal = cwd.flatMap { hookSignals[$0] }
                let state = BoardRules.state(agent: controller.agent, commandRunning: controller.activity == .commandRunning,
                                             lastOutputAt: controller.lastOutputAt, inputAt: controller.lastInputAt,
                                             title: controller.agentTitle, notice: controller.lastNotification?.message,
                                             noticeAt: controller.lastNotification?.at, hook: signal?.meaning, hookAt: signal?.at,
                                             now: now, quietSeconds: quiet)
                let column = state.column
                if columnSince[pane]?.column != column { columnSince[pane] = (column, now) }
                let subtitle = subtitle(for: controller, cwd: cwd)
                next.append(Card(id: pane, sessionID: session.id, sessionName: session.name,
                                 projectName: project?.name ?? "", agent: controller.agent,
                                 subtitle: subtitle == session.name ? "" : subtitle, state: state,
                                 since: columnSince[pane]?.at ?? now))
            }
        }
        let live = Set(next.map(\.id))
        columnSince = columnSince.filter { live.contains($0.key) }
        let previous = cards
        if next != cards { cards = next }
        noticeWaiting(previous: previous, next: next, quiet: quiet)
    }

    private var lastBadge = -1

    /// A card that just entered Waiting gets one notification, unless the user is already looking
    /// at that pane. The Dock badge always shows how many are waiting.
    private func noticeWaiting(previous: [Card], next: [Card], quiet: Double) {
        let waiting = next.filter { $0.state.column == .waiting }.count
        if waiting != lastBadge { lastBadge = waiting; setBadge(waiting) }
        guard runtime.config.agents.notify else { return }
        let inFront = isInFront()
        for card in WaitingNotifier.newlyWaiting(previous: previous, next: next)
        where WaitingNotifier.shouldNotify(card: card, focusedPane: runtime.focusedPaneID, appActive: inFront) {
            deliverWaiting(card, WaitingNotifier.reason(for: card.state, quietSeconds: quiet))
        }
    }

    public func cards(in column: BoardColumn) -> [Card] {
        cards.filter { $0.state.column == column }
    }

    public var waitingCount: Int { cards(in: .waiting).count }

    public func isWaiting(session: SessionID) -> Bool {
        cards.contains { $0.sessionID == session && $0.state.column == .waiting }
    }

    private func subtitle(for controller: TerminalSessionController, cwd: String?) -> String {
        if let live = controller.agentTitle?.name { return live }
        if controller.agent.isAgent, let cwd,
           let match = history.first(where: { $0.agent == controller.agent && Self.normalize($0.projectPath) == cwd }) {
            return match.title
        }
        if let command = controller.foregroundCommand { return command }
        if let cwd { return cwd.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }
        return ""
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.hasPrefix("/private/") { p = String(p.dropFirst("/private".count)) }
        return p
    }

    // MARK: - History

    public func reloadHistory() async {
        guard !isLoadingHistory else { return }   // a scan is already on its way
        isLoadingHistory = true
        let paths = runtime.paths
        let (loaded, retention, stats): ([PastSession], Int, ActivityStats) = await Task.detached(priority: .userInitiated) {
            let openCode = OpenCodeSessionSource(), pi = PiSessionSource()
            var all = ClaudeSessionSource().scan() + CodexSessionSource().scan() + openCode.scan() + pi.scan()
            all += AnteSessionHistoryStore(paths: paths).all().map(\.asPastSession)
            let retention = ClaudeHookInstaller(eventFile: paths.claudeHookEventFile).retentionDays()
            let stats = ActivityStats.build(events: ClaudeHistorySource().events() + CodexHistorySource().events() + openCode.events() + pi.events())
            return (all.sorted { $0.modifiedAt > $1.modifiedAt }, retention, stats)
        }.value
        history = loaded
        claudeRetentionDays = retention
        activity = stats
        isLoadingHistory = false
        refresh()
    }

    public var filteredHistory: [PastSession] {
        var rows = history
        if let agentFilter { rows = rows.filter { $0.agent == agentFilter } }
        if !query.isEmpty {
            rows = FuzzyMatcher.rank(rows, query: query, text: { "\($0.title) \($0.projectName) \($0.agent.displayName)" })
        }
        return rows
    }

    public var historyAgents: [AgentKind] {
        Array(Set(history.map(\.agent))).sorted { $0.displayName < $1.displayName }
    }
}
