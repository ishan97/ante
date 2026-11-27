// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Restore.swift
import Foundation
import AnteCore
import AnteTerm

/// `[sessions] restore`: every session's panes are recorded as they change (folders, splits, the
/// agent in front), and the next launch rebuilds them, typing each agent's resume command into
/// its pane once the shell is ready. Screen contents are never saved.
extension WorkspaceRuntime {
    // MARK: - Recording

    /// Saves a session's current panes into its persisted `layout`. Cheap when nothing changed.
    func recordLayout(for session: SessionID) {
        guard !isQuitting, let tree = layouts[session] else { return }
        store.setLayout(savedLayout(tree), for: session)
    }

    func recordAllLayouts() {
        for session in layouts.keys { recordLayout(for: session) }
    }

    private func savedLayout(_ tree: SplitTree) -> SavedLayout {
        switch tree {
        case let .leaf(pane):
            return .pane(savedPane(pane))
        case let .split(axis, ratio, first, second):
            return .split(axis == .horizontal ? .horizontal : .vertical, ratio: ratio,
                          first: savedLayout(first), second: savedLayout(second))
        }
    }

    func savedPane(_ pane: PaneID) -> SavedPane {
        let controller = controllers[pane]
        let session = self.session(for: pane).flatMap { id in store.state.sessions.first { $0.id == id } }
        let directory = controller?.currentDirectory ?? session?.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        guard let controller, controller.state == .running, controller.agent.isAgent else {
            return SavedPane(workingDirectory: directory)
        }
        let agent = controller.agent
        let folder = SessionBoardModel.normalize(directory.path)
        let sharesFolder = controllers.contains { other in
            other.key != pane && other.value.state == .running && other.value.agent == agent
                && other.value.currentDirectory.map { SessionBoardModel.normalize($0.path) } == folder
        }
        let hookID = foregroundSince[pane].flatMap {
            board?.hookSessionID(agent: agent, directory: directory, since: $0, process: controller.foreground?.pid)
        }
        var saved = Self.savedAgentPane(agent: agent, directory: directory, commandLine: controller.foreground?.commandLine ?? [],
                                        liveSessionID: liveConversation(in: pane).id, hookSessionID: hookID, sharesFolder: sharesFolder)
        saved.accountID = account(in: pane)?.id
        return saved
    }

    /// Which conversation an agent pane comes back to. The id it was started with comes first (it
    /// is this pane's for certain); else the one a hook reported in this folder since the agent
    /// started — which names only the folder, so it counts only when no other pane runs the same
    /// agent there. Without an id the pane continues the agent's latest conversation in the
    /// folder, unless another pane shares it: then the agent's picker opens, so two panes never
    /// end up in one conversation.
    /// `liveSessionID` (the agent's own record of its open conversation, or this pane's hook) is
    /// exact and follows `/clear` and `/resume`, so it comes before the command line.
    static func savedAgentPane(agent: AgentKind, directory: URL, commandLine: [String], liveSessionID: String? = nil,
                               hookSessionID: String?, sharesFolder: Bool) -> SavedPane {
        let id = liveSessionID ?? agent.sessionID(fromCommandLine: commandLine) ?? (sharesFolder ? nil : hookSessionID)
        return SavedPane(workingDirectory: directory, agent: agent, agentSessionID: id, mayContinueLatest: !sharesFolder)
    }

    // MARK: - Restoring

    /// Rebuilds every sidebar session from its saved layout and starts its shells. Called once
    /// at launch, before anything is shown.
    func restoreSessions() {
        for session in store.state.sessions where session.isScratch {
            store.removeSession(session.id)
        }
        for session in store.allVisibleSessions {
            let saved = session.layout ?? .pane(SavedPane(workingDirectory: session.workingDirectory))
            let project = store.state.projects.first { $0.id == session.projectID }
            layouts[session.id] = rebuild(saved, session: session.id, projectRoot: project?.rootDirectory)
        }
    }

    private func rebuild(_ saved: SavedLayout, session: SessionID, projectRoot: URL?) -> SplitTree {
        switch saved {
        case let .pane(savedPane):
            let pane = PaneID()
            let wanted = savedPane.workingDirectory
            let directory = [wanted, projectRoot].compactMap { $0 }.first(where: Self.isDirectory)
                ?? FileManager.default.homeDirectoryForCurrentUser
            makeController(pane: pane, session: session, directory: directory)
            // An agent resumes only in its own folder: "continue the latest" elsewhere would open
            // some other conversation.
            if directory == wanted, let command = savedPane.resumeCommand {
                restoreAgent(command, savedPane: savedPane, session: session, pane: pane, folder: directory)
            }
            return .leaf(pane)
        case let .split(axis, ratio, first, second):
            return .split(axis == .horizontal ? .horizontal : .vertical, ratio: min(max(ratio, 0.1), 0.9),
                          first: rebuild(first, session: session, projectRoot: projectRoot),
                          second: rebuild(second, session: session, projectRoot: projectRoot))
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Asking which account restored agents run as

    /// An account-aware agent comes back as the default or only account; with a real choice and
    /// no default, its pane waits in `pendingRestores` for the restore sheet.
    private func restoreAgent(_ command: String, savedPane: SavedPane, session: SessionID, pane: PaneID, folder: URL) {
        guard let agent = savedPane.agent.flatMap(AccountAgent.init(agentKind:)) else {
            type(command, intoPaneWhenReady: pane)
            return
        }
        guard accounts.needsAsking(agent) else {
            type(self.command(command, as: accounts.automaticAccount(for: agent)), intoPaneWhenReady: pane)
            return
        }
        let name = store.state.sessions.first { $0.id == session }?.name ?? agent.displayName
        pendingRestores.append(RestoreItem(pane: pane, agent: agent, title: name, folder: folder.lastPathComponent, base: command,
                                           preselected: accounts.account(id: savedPane.accountID, agent: agent)))
    }

    /// Starts each waiting agent as the chosen account (nil: as the agent starts by itself).
    public func confirmRestore(_ choices: [PaneID: AgentAccount?]) {
        let items = pendingRestores
        pendingRestores = []
        for item in items {
            let account = choices[item.pane] ?? item.preselected
            type(command(item.base, as: account), intoPaneWhenReady: item.pane)
        }
    }

    /// Leaves the waiting panes as plain shells.
    public func skipRestoreAgents() {
        pendingRestores = []
    }

    // MARK: - Typing the resume command

    /// Types `command` into the pane at its shell's first prompt, or after 10 s for a shell
    /// without integration. Panes of one session share its id on the event bus, so this listens
    /// on the pane's own controller.
    func type(_ command: String, intoPaneWhenReady pane: PaneID) {
        guard let controller = controllers[pane] else { return }
        // A shell already at its prompt (the person took a while to choose) gets it now.
        if controller.hasShownPrompt, controller.activity == .idle {
            if controller.lastTypedAt == nil { controller.view.send(txt: command + "\n") }
            return
        }
        let fallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.deliverPaneCommand(to: pane)
        }
        pendingPaneCommands[pane] = (command, fallback)
        controller.onPromptStarted = { [weak self] in self?.deliverPaneCommand(to: pane) }
    }

    private func deliverPaneCommand(to pane: PaneID) {
        guard let pending = pendingPaneCommands.removeValue(forKey: pane) else { return }
        pending.fallback.cancel()
        guard let controller = controllers[pane] else { return }
        controller.onPromptStarted = nil
        // If the person already started typing, do not type over them.
        if controller.lastTypedAt != nil { return }
        controller.view.send(txt: pending.command + "\n")
    }

    /// Drops what the restore bookkeeping holds for a pane that closed.
    func forgetPane(_ pane: PaneID) {
        pendingPaneCommands.removeValue(forKey: pane)?.fallback.cancel()
        foregroundSince[pane] = nil
    }
}
