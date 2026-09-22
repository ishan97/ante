// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime.swift
import AppKit
import Observation
import os
import SwiftTerm
import AnteCore
import AnteTerm
import AnteTheme

/// Maps persisted sessions to live terminals. Owns focus, split layouts, appearance, and the
/// quit path (file sessions into History, kill process groups).
@MainActor
@Observable
public final class WorkspaceRuntime {
    private static let logger = Logger(subsystem: "ante.term", category: "runtime")

    public typealias LaunchFactory = @MainActor (URL) -> ShellLaunch

    public let paths: AppPaths
    public let store: WorkspaceStore
    public let bus = RunEventBus()
    public private(set) var config: AnteConfig
    public private(set) var appearance: TerminalAppearance
    public private(set) var focusedPaneID: PaneID?
    public var isSidebarVisible = true
    /// The most recent config problem, shown as a banner. Set by the app's config loader/watcher.
    public var configError: ConfigError?
    public var isSearchVisible = false
    public var isPaletteVisible = false
    public var isSessionsViewerVisible = false
    /// The to-do & notes popover under the toolbar's checklist button.
    public var isScratchpadVisible = false
    /// Width of the toolbar's control cluster (measured), so the window knows where the
    /// title-bar band ends on the right and clicks on buttons are never mistaken for a drag.
    public var headerControlsWidth: CGFloat = 200
    public let scratchpad: ScratchpadModel
    /// The focus timer under the toolbar's timer button.
    public var isPomodoroVisible = false
    public let pomodoro = PomodoroModel()
    /// Installed by the app at launch (Sparkle); nil in tests, previews, and unsigned builds.
    public var updater: (any UpdateChecking)?
    /// The Sessions view's model. Created after `self` exists; never nil after init.
    public private(set) var board: SessionBoardModel!
    let historyStore: AnteSessionHistoryStore
    var pendingResumes: Set<SessionID> = []
    var resumeWaiters: [SessionID: [Task<Void, Never>]] = [:]

    private let themeLoader: ThemeLoader
    private let launchFactory: LaunchFactory
    private var layouts: [SessionID: SplitTree] = [:]
    private var controllers: [PaneID: TerminalSessionController] = [:]
    private var paneSessions: [PaneID: SessionID] = [:]
    private var placeholders: [PaneID: TerminalSessionController] = [:]

    public init(paths: AppPaths, config: AnteConfig, launchFactory: @escaping LaunchFactory) {
        self.paths = paths
        self.config = config
        self.launchFactory = launchFactory
        self.store = WorkspaceStore(stateStore: StateStore(paths: paths))
        // Scrollback was persisted here before 0.1.0 quit-to-History; clear anything left behind.
        try? FileManager.default.removeItem(at: paths.scrollbackDirectory)
        self.themeLoader = ThemeLoader(userDirectory: paths.themesDirectory)
        self.historyStore = AnteSessionHistoryStore(paths: paths)
        self.scratchpad = ScratchpadModel(store: ScratchpadStore(paths: paths))
        FontRegistrar.registerBundledFonts()
        self.appearance = Self.makeAppearance(config: config, loader: themeLoader)
        self.board = SessionBoardModel(runtime: self)
        // The timer's chime is the same sound the user picked for "waiting for you".
        pomodoro.notify = { [weak self] phase in
            PomodoroModel.systemNotify(phase, sound: self?.config.agents.notifySound ?? "Glass")
        }
        ensureDefaults()
    }

    // MARK: - Defaults

    private func ensureDefaults() {
        if store.state.projects.isEmpty {
            let home = store.addProject(rootDirectory: FileManager.default.homeDirectoryForCurrentUser)
            store.renameProject(home.id, to: "Home")
        }
        // A launch starts clean. Sessions normally go to History on quit; after a crash or a
        // forced quit they are still here, so file them now, then open one fresh session.
        fileSessionsIntoHistory()
        if let project = store.state.orderedProjects.first {
            store.addSession(in: project.id)
        }
        // Scratch sessions came from the old hotkey panel; state files may still carry one.
        if store.state.focusedSessionID == nil || store.focusedSession?.isScratch == true {
            store.focus(store.allVisibleSessions.first?.id)
        }
    }

    // MARK: - Appearance

    public var prefersDark: Bool {
        switch config.theme.appearance {
        case .dark: return true
        case .light: return false
        case .system: return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private static func makeAppearance(config: AnteConfig, loader: ThemeLoader) -> TerminalAppearance {
        let isDark: Bool
        switch config.theme.appearance {
        case .dark: isDark = true
        case .light: isDark = false
        case .system: isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
        }
        var theme = loader.resolve(name: config.theme.name, preferDark: isDark)
        // A custom window background replaces the theme's, and decides light vs dark chrome.
        if let hex = config.theme.background, let color = ThemeColor(hex: hex), let parsed = HexColor.parse(hex) {
            theme.background = color
            theme.appearance = parsed.luminance < 0.5 ? .dark : .light
        }
        let font = FontResolver.resolve(family: config.font.family, size: config.font.size)
        return TerminalAppearance(theme: theme, font: font, cursorStyle: Self.cursorStyle(config.cursor))
    }

    static func cursorStyle(_ cursor: AnteConfig.Cursor) -> CursorStyle {
        switch (cursor.style, cursor.blink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        }
    }

    public func applyConfig(_ newConfig: AnteConfig) {
        let oldOpacity = terminalOpacity
        config = newConfig
        let next = Self.makeAppearance(config: newConfig, loader: themeLoader)
        let appearanceChanged = next.theme != appearance.theme || next.font != appearance.font || next.cursorStyle != appearance.cursorStyle
        appearance = next
        for controller in controllers.values {
            if appearanceChanged { controller.apply(appearance) }
            if terminalOpacity != oldOpacity { controller.setBackgroundOpacity(terminalOpacity) }
            controller.view.confirmMultilinePaste = newConfig.security.confirmMultilinePaste
        }
    }

    /// How opaque the terminal's own background is. A translucent window paints one tint behind
    /// everything, so the terminal draws none of its own (a second layer would show as a darker
    /// box behind the text); with a wallpaper it fades by the wallpaper's opacity.
    public var terminalOpacity: CGFloat {
        if config.theme.opacity < 1 { return 0 }
        return CGFloat(config.wallpaper.path.isEmpty ? 1.0 : 1.0 - min(max(config.wallpaper.opacity, 0), 0.9))
    }

    // MARK: - Sessions ↔ panes

    public func existingLayout(for session: SessionID) -> SplitTree? {
        layouts[session]
    }

    /// The layout for a session, creating its first pane (and spawning its shell) on first use.
    public func layout(for session: SessionID) -> SplitTree {
        if let existing = layouts[session] { return existing }
        let pane = PaneID()
        let tree = SplitTree.leaf(pane)
        layouts[session] = tree
        _ = makeController(pane: pane, session: session, directory: nil)
        return tree
    }

    public func controller(for pane: PaneID) -> TerminalSessionController {
        if let existing = controllers[pane] { return existing }
        // A pane in a layout always has a controller. SwiftUI can still ask for one a frame after
        // a close; hand back an idle placeholder that never spawns and is never registered.
        if let placeholder = placeholders[pane] { return placeholder }
        placeholders.removeAll()   // one frame's worth is all a placeholder is for
        let placeholder = TerminalSessionController(sessionID: paneSessions[pane] ?? SessionID(),
                                                    launch: launchFactory(FileManager.default.homeDirectoryForCurrentUser),
                                                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser, bus: bus)
        placeholders[pane] = placeholder
        return placeholder
    }

    public func session(for pane: PaneID) -> SessionID? {
        paneSessions[pane]
    }

    @discardableResult
    private func makeController(pane: PaneID, session: SessionID, directory: URL?) -> TerminalSessionController {
        let persisted = store.state.sessions.first { $0.id == session }
        let directory = directory ?? persisted?.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let launch = launchFactory(directory)
        let controller = TerminalSessionController(sessionID: session, launch: launch, workingDirectory: directory, bus: bus)
        controller.apply(appearance)
        controller.setBackgroundOpacity(terminalOpacity)
        controller.view.confirmMultilinePaste = config.security.confirmMultilinePaste
        controller.view.onOpenLink = { [weak self] match in self?.openLink(match) }
        // Claude Code names its session in the window title; show that name in the sidebar
        // unless the user has named the session themselves.
        controller.onAgentTitle = { [weak self] title in
            if let name = title?.name { self?.store.setAutoName(name, for: session) }
        }
        // Keep the persisted folder current, so a crash still files the session where it was.
        controller.onDirectoryChanged = { [weak self] url in self?.store.updateSession(session, workingDirectory: url) }
        controllers[pane] = controller
        paneSessions[pane] = session
        controller.start()
        return controller
    }

    public func open(session id: SessionID) {
        // Opening a session is always a request to *see* it: leave the Sessions board.
        isSessionsViewerVisible = false
        store.focus(id)
        let tree = layout(for: id)
        if let current = focusedPaneID, tree.contains(current) { return }
        focusedPaneID = tree.paneIDs.first
    }

    @discardableResult
    public func newSession(in project: ProjectID) -> Session {
        let session = store.addSession(in: project)
        open(session: session.id)
        return session
    }

    public func closeSession(_ id: SessionID) {
        recordHistory(for: id)
        for pane in layouts[id]?.paneIDs ?? [] {
            controllers[pane]?.terminate()
            controllers[pane] = nil
            paneSessions[pane] = nil
        }
        layouts[id] = nil
        let wasFocused = store.state.focusedSessionID == id
        store.removeSession(id)
        if wasFocused, let next = store.state.focusedSessionID {
            open(session: next)
        } else if wasFocused {
            focusedPaneID = nil
        }
    }

    /// Remembers a closing session (not scratch) so History can reopen it.
    /// The controller that stands for a session: the focused pane's if it belongs to the session,
    /// else the first pane's.
    private func primaryController(for id: SessionID) -> TerminalSessionController? {
        guard let tree = existingLayout(for: id) else { return nil }
        let pane = tree.paneIDs.first { $0 == focusedPaneID } ?? tree.paneIDs.first
        return pane.flatMap { controllers[$0] }
    }

    private func closedSession(for session: Session) -> ClosedSession {
        let project = store.state.projects.first { $0.id == session.projectID }
        let controller = primaryController(for: session.id)
        let cwd = controller?.currentDirectory ?? session.workingDirectory
        return ClosedSession(name: session.name, workingDirectory: cwd.path,
                             projectPath: project?.rootDirectory.path ?? cwd.path,
                             lastCommand: controller?.foregroundCommand.map(Self.programName) ?? session.lastCommand,
                             agent: controller?.agent ?? .shell)
    }

    /// Only sessions with an agent in the foreground go to History: an agent session can be
    /// picked up again (its own history has the resume command, and the entry keeps the project
    /// folder), whereas a closed shell or a finished command has nothing to come back to.
    private func isWorthRemembering(_ session: Session) -> Bool {
        guard let controller = primaryController(for: session.id) else { return false }
        return controller.agent.isAgent
    }

    private func recordHistory(for id: SessionID) {
        guard let session = store.state.sessions.first(where: { $0.id == id }), !session.isScratch,
              isWorthRemembering(session) else { return }
        do { try historyStore.append(closedSession(for: session)) } catch {
            Self.logger.error("history append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves every visible session into History in one write and removes them from the sidebar.
    /// Called on quit, and at launch for anything a crash left behind.
    private func fileSessionsIntoHistory() {
        let sessions = store.allVisibleSessions
        let closed = sessions.filter(isWorthRemembering).map(closedSession(for:))
        if !closed.isEmpty {
            do { try historyStore.append(contentsOf: closed) } catch {
                Self.logger.error("history append failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for session in sessions { store.removeSession(session.id) }
    }

    // MARK: - Panes

    public func focusPane(_ pane: PaneID) {
        guard let session = paneSessions[pane] else { return }
        focusedPaneID = pane
        store.focus(session)
    }

    public func splitFocusedPane(axis: SplitAxis, before: Bool = false) {
        guard let current = focusedPaneID, let session = paneSessions[current], let tree = layouts[session] else { return }
        let newPane = PaneID()
        layouts[session] = tree.splitting(pane: current, axis: axis, newPane: newPane, before: before)
        let inherited = controllers[current]?.currentDirectory
        makeController(pane: newPane, session: session, directory: inherited)
        focusedPaneID = newPane
    }

    public func closeFocusedPane() {
        guard let current = focusedPaneID else { return }
        closePane(current)
    }

    /// Closes one pane (its shell's process group included). The last pane closes the session.
    public func closePane(_ pane: PaneID) {
        guard let session = paneSessions[pane], let tree = layouts[session] else { return }
        if let remaining = tree.removing(pane: pane) {
            controllers[pane]?.terminate()
            controllers[pane] = nil
            paneSessions[pane] = nil
            layouts[session] = remaining
            if focusedPaneID == pane || focusedPaneID.map({ !remaining.contains($0) }) ?? true {
                focusedPaneID = tree.neighbor(of: pane, direction: .left) ?? tree.neighbor(of: pane, direction: .up)
                    ?? remaining.paneIDs.first
            }
        } else {
            closeSession(session)
        }
    }

    /// How many panes the focused session has — the close button shows only when there are several.
    public func paneCount(for session: SessionID) -> Int {
        layouts[session]?.paneIDs.count ?? 0
    }

    public func focusNeighbor(_ direction: PaneDirection) {
        guard let current = focusedPaneID, let session = paneSessions[current], let tree = layouts[session],
              let target = tree.neighbor(of: current, direction: direction) else { return }
        focusedPaneID = target
    }

    public func setRatio(_ ratio: Double, forSplitContaining pane: PaneID) {
        guard let session = paneSessions[pane], let tree = layouts[session] else { return }
        layouts[session] = tree.withRatio(ratio, forSplitContaining: pane)
    }

    // MARK: - Session navigation

    public func focusSession(index: Int) {
        let sessions = store.allVisibleSessions
        guard sessions.indices.contains(index) else { return }
        open(session: sessions[index].id)
    }

    public func focusSession(offset: Int) {
        let sessions = store.allVisibleSessions
        guard !sessions.isEmpty else { return }
        let currentIndex = sessions.firstIndex { $0.id == store.state.focusedSessionID } ?? 0
        let next = ((currentIndex + offset) % sessions.count + sessions.count) % sessions.count
        open(session: sessions[next].id)
    }

    // MARK: - Quit

    /// Quitting files every session into History (name, folder, last command), so the next launch
    /// starts with one fresh session and nothing half-remembered. Projects stay. Then the state is
    /// saved synchronously and every process group killed. Safe to call more than once.
    public func prepareForQuit() {
        scratchpad.flush()
        fileSessionsIntoHistory()
        store.saveNow()
        for controller in controllers.values {
            controller.terminate()
        }
    }
}

extension WorkspaceRuntime {
    /// The program of a command line, without its arguments: History remembers `curl`, not the
    /// header that carried a token.
    static func programName(_ commandLine: String) -> String {
        let first = commandLine.split(separator: " ", maxSplits: 1).first.map(String.init) ?? commandLine
        return (first as NSString).lastPathComponent
    }
}
