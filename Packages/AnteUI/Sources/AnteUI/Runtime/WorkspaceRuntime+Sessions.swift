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
    public func resume(_ past: PastSession) {
        // Standardize once so the project root and the session cwd agree (`/private/tmp` → `/tmp`).
        let directory = URL(fileURLWithPath: (past.projectPath as NSString).standardizingPath, isDirectory: true)
        let project = store.orderedProjectContaining(directory) ?? store.addProject(rootDirectory: directory)
        let name = past.title.count > 32 ? String(past.title.prefix(31)) + "…" : past.title
        let session = store.addSession(in: project.id, name: name, workingDirectory: directory)
        // Listen before the shell spawns: a fast shell prints its prompt within milliseconds.
        if let command = past.resumeCommand {
            typeAfterFirstPrompt(command, in: session.id)
        }
        open(session: session.id)
        isSessionsViewerVisible = false
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
        // If the person already started typing, do not type over them.
        if let typed = controller.lastInputAt, typed > Date().addingTimeInterval(-10) { return }
        controller.view.send(txt: command + "\n")
    }
}
