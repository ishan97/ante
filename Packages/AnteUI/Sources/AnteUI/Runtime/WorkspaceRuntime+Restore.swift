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
        let hookID = foregroundSince[pane].flatMap { board?.hookSessionID(agent: agent, directory: directory, since: $0) }
        return Self.savedAgentPane(agent: agent, directory: directory, commandLine: controller.foreground?.commandLine ?? [],
                                   hookSessionID: hookID, sharesFolder: sharesFolder)
    }

    /// Which conversation an agent pane comes back to. The id it was started with comes first (it
    /// is this pane's for certain); else the one a hook reported in this folder since the agent
    /// started — which names only the folder, so it counts only when no other pane runs the same
    /// agent there. Without an id the pane continues the agent's latest conversation in the
    /// folder, unless another pane shares it: then the agent's picker opens, so two panes never
    /// end up in one conversation.
    static func savedAgentPane(agent: AgentKind, directory: URL, commandLine: [String],
                               hookSessionID: String?, sharesFolder: Bool) -> SavedPane {
        let id = agent.sessionID(fromCommandLine: commandLine) ?? (sharesFolder ? nil : hookSessionID)
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
                type(command, intoPaneWhenReady: pane)
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

    // MARK: - Typing the resume command

    /// Types `command` into the pane at its shell's first prompt, or after 10 s for a shell
    /// without integration. Panes of one session share its id on the event bus, so this listens
    /// on the pane's own controller.
    func type(_ command: String, intoPaneWhenReady pane: PaneID) {
        guard let controller = controllers[pane] else { return }
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
