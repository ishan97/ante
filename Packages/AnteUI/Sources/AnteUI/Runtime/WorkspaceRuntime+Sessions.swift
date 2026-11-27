// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Sessions.swift
import Foundation
import AnteCore
import AnteTerm

extension WorkspaceRuntime {
    /// The first pane's controller for a session that has been opened, if any.
    public func liveController(for session: SessionID) -> TerminalSessionController? {
        guard let pane = existingLayout(for: session)?.paneIDs.first else { return nil }
        return controller(for: pane)
    }

    /// Opens a session in the past session's project and, once the shell shows its first prompt,
    /// types the agent's resume command. Without a resume command it just reopens the folder.
    public func resume(_ past: PastSession, account: AgentAccount? = nil) {
        // A conversation already open in a pane is shown there: a second process would write it too.
        if let conversation = past.conversationID,
           let pane = paneRunning(conversation: conversation, agentKind: past.agent, folder: past.projectPath, createdAt: past.createdAt) {
            focusPane(pane)
            isSessionsViewerVisible = false
            return
        }
        // Standardize once so the project root and the session cwd agree (`/private/tmp` → `/tmp`).
        let directory = URL(fileURLWithPath: (past.projectPath as NSString).standardizingPath, isDirectory: true)
        let project = store.orderedProjectContaining(directory) ?? store.addProject(rootDirectory: directory)
        let name = past.title.count > 32 ? String(past.title.prefix(31)) + "…" : past.title
        let session = store.addSession(in: project.id, name: name, workingDirectory: directory)
        // Listen before the shell spawns: a fast shell prints its prompt within milliseconds.
        if let command = past.resumeCommand {
            typeAfterFirstPrompt(self.command(command, as: account), in: session.id)
        }
        open(session: session.id)
        isSessionsViewerVisible = false
    }

    /// The pane already showing conversation `id` of `agent`, if any. Claude and Codex are read
    /// from their own records (`paneRunning(conversation:agent:)`); other agents from the id they
    /// were started with. Antigravity panes started without one are matched in the conversation's
    /// `folder`: `agy --continue` opened the folder's latest conversation (agy's own record of it),
    /// and plain `agy` started a new one, which can only be this conversation if it was created
    /// after that process started. Of several such panes, the one started last wins.
    func paneRunning(conversation id: String, agentKind: AgentKind, folder: String? = nil, createdAt: Date? = nil) -> PaneID? {
        if let agent = AccountAgent(agentKind: agentKind) { return paneRunning(conversation: id, agent: agent) }
        let panes = controllers.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        var guesses: [(pane: PaneID, started: Date)] = []
        var latest: [String: String]?
        for pane in panes {
            guard let controller = controllers[pane], controller.agent == agentKind, let info = controller.foreground else { continue }
            if let started = agentKind.sessionID(fromCommandLine: info.commandLine) {
                if started == id { return pane }
                continue
            }
            guard agentKind == .antigravity, let folder, let here = controller.currentDirectory?.path,
                  Self.samePlace(here, folder), let started = Self.processStart(info.pid) else { continue }
            if info.commandLine.contains("--continue") {
                if latest == nil { latest = AntigravitySessionSource.lastConversations() }
                if latest?[here] == id || latest?[folder] == id || latest?[Self.realPath(here)] == id { guesses.append((pane, started)) }
            } else if let createdAt, createdAt >= started.addingTimeInterval(-2) {
                guesses.append((pane, started))
            }
        }
        return guesses.max { $0.started < $1.started }?.pane
    }

    /// The two paths name the same folder (`/tmp` and `/private/tmp` included).
    static func samePlace(_ a: String, _ b: String) -> Bool { a == b || realPath(a) == realPath(b) }

    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// When process `pid` started.
    static func processStart(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6)
    }

    /// Waits for the session's first OSC 133;A (the prompt is ready), then sends the command.
    /// Falls back to sending after 10 s so a shell without integration still gets it.
    func typeAfterFirstPrompt(_ command: String, in session: SessionID) {
        pendingResumes.insert(session)
        let stream = bus.events()
        // One task waits for the prompt, the other is the 10 s fallback; whichever delivers
        // cancels the other, so neither outlives the resume (with integration off, no prompt
        // event ever comes).
        let waiter = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { return }
                guard event.sessionID == session else { continue }
                if case .promptStarted = event.event {
                    await self?.deliverPendingResume(command, to: session)
                    return
                }
            }
        }
        let fallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await self?.deliverPendingResume(command, to: session)
        }
        resumeWaiters[session] = [waiter, fallback]
    }

    private func deliverPendingResume(_ command: String, to session: SessionID) {
        resumeWaiters.removeValue(forKey: session)?.forEach { $0.cancel() }
        guard pendingResumes.remove(session) != nil, let controller = liveController(for: session) else { return }
        // If the person already started typing, do not type over them. Return or an arrow to
        // wake the pane leaves the line empty, so it does not count.
        if let typed = controller.lastTypedAt, typed > Date().addingTimeInterval(-10) { return }
        controller.view.send(txt: command + "\n")
    }
}
