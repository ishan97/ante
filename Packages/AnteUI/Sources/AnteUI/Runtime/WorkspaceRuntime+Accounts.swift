// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Accounts.swift
import Foundation
import AnteCore
import AnteTerm

/// Accounts in the running workspace: which account a pane's agent runs as, and starting an agent
/// as a chosen account.
extension WorkspaceRuntime {
    /// The account the agent in front of `pane` runs as, read from the agent process's own
    /// environment. Nil for a shell, a non-account agent, or a folder Ante doesn't know.
    public func account(in pane: PaneID) -> AgentAccount? {
        guard let controller = controllers[pane], let info = controller.foreground,
              let agent = AccountAgent(agentKind: controller.agent) else { return nil }
        return AccountResolver.account(for: info.environment, agent: agent, accounts: accounts.accounts, paths: accounts.paths)
    }

    /// The agent `base` command (`claude`, `claude --resume <id>`) as `account`.
    /// Re-links the account's shared items first (one the agent created since the account was
    /// added, e.g. a new database), so it never quietly starts with a private copy.
    public func command(_ base: String, as account: AgentAccount?) -> String {
        if let account, !account.isDefaultFolder { try? AccountFolder.prepare(account, paths: accounts.paths) }
        return AccountLaunch.command(base, account: account, paths: accounts.paths)
    }

    /// Opens a new session in `project` and starts the agent there as `account` (nil: as the agent
    /// starts by itself, which asks in the terminal when there is a choice).
    public func startAgent(_ agent: AccountAgent, account: AgentAccount?, inNewSessionOf project: ProjectID) {
        let session = newSession(in: project)
        guard let pane = layout(for: session.id).paneIDs.first else { return }
        type(command(agent.executable, as: account), intoPaneWhenReady: pane)
        open(session: session.id)
    }
}

/// A restored pane whose agent waits for the person to choose an account.
public struct RestoreItem: Identifiable, Equatable, Sendable {
    public let pane: PaneID
    public let agent: AccountAgent
    /// The session's name, and the folder the agent works in.
    public let title: String
    public let folder: String
    /// The resume command without an account (`claude --resume <id>`).
    public let base: String
    /// The account the pane last ran as, if Ante still knows it.
    public let preselected: AgentAccount?

    public var id: PaneID { pane }
}

extension WorkspaceRuntime {
    /// The conversation the agent in `pane` has open now, and whether it is mid-reply. Claude:
    /// its live-process file, else the pane's latest hook event. Codex: its command line, else
    /// the conversation file it has open.
    public func liveConversation(in pane: PaneID) -> (id: String?, isBusy: Bool) {
        guard let controller = controllers[pane], let info = controller.foreground,
              let agent = AccountAgent(agentKind: controller.agent) else { return (nil, false) }
        switch agent {
        case .claude:
            let folder = info.environment[agent.configVariable].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? agent.defaultFolder(home: accounts.paths.home)
            if let live = LiveConversationReader.claude(pid: info.pid, configDirectory: folder) { return (live.id, live.isBusy) }
            let since = foregroundSince[pane] ?? .distantPast
            return (board?.hookSessionID(pane: pane, agent: .claude, since: since, process: info.pid), false)
        case .codex:
            let id = AgentKind.codex.sessionID(fromCommandLine: info.commandLine)
                ?? LiveConversationReader.codexID(openFiles: LiveConversationReader.openFiles(pid: info.pid))
            return (id, false)
        }
    }

    /// The pane whose `agent` has conversation `id` open, if any. When a pane's live conversation
    /// can't be read, the id it was started with counts: better to focus a pane that may have
    /// moved on than to start a second writer.
    public func paneRunning(conversation id: String, agent: AccountAgent) -> PaneID? {
        controllers.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first { pane in
            guard let controller = controllers[pane], controller.agent == agent.agentKind else { return false }
            if let live = liveConversation(in: pane).id { return live == id }
            return agent.agentKind.sessionID(fromCommandLine: controller.foreground?.commandLine ?? []) == id
        }
    }
}

/// What a switch did.
public enum SwitchOutcome: Equatable, Sendable {
    /// The conversation continues on the new account.
    case resumed(id: String)
    /// The conversation wasn't known: the agent's own picker opened on the new account.
    case openedPicker
    /// Nothing was typed: same account, no agent, or the agent didn't exit in time.
    case cancelled
}

extension WorkspaceRuntime {
    /// Moves the conversation in `pane` to `account`: ends the agent, waits until its process is
    /// gone and the shell prompt is back, then resumes the same conversation as `account`. Never
    /// types anything if the agent doesn't exit within `timeout`.
    public func switchAccount(pane: PaneID, to account: AgentAccount, timeout: TimeInterval = 10) async -> SwitchOutcome {
        guard let controller = controllers[pane], let agent = AccountAgent(agentKind: controller.agent), agent == account.agent,
              let oldPID = controller.foreground?.pid, self.account(in: pane) != account else { return .cancelled }
        let id = liveConversation(in: pane).id
        // Ctrl-C interrupts a reply, clears typed text, and a second one exits (Claude and Codex
        // alike); keep sending until the process is gone.
        let deadline = Date().addingTimeInterval(timeout)
        var exited = false
        while Date() < deadline {
            controller.view.send(txt: "\u{03}")
            try? await Task.sleep(for: .milliseconds(350))
            controller.probeNow()
            // Gone, not merely out of front: a tool the agent runs also takes the foreground.
            if kill(oldPID, 0) != 0 {
                exited = true
                break
            }
        }
        guard exited else { return .cancelled }
        // The shell prompt is back before anything is typed.
        while Date() < deadline, controller.activity != .idle || controller.agent != .shell {
            try? await Task.sleep(for: .milliseconds(50))
            controller.probeNow()
        }
        // Typed only into the shell itself (activity alone is always idle without integration).
        guard controller.activity == .idle, controller.agent == .shell, kill(oldPID, 0) != 0 else { return .cancelled }
        let base: String
        switch (agent, id) {
        case let (.claude, id?): base = AgentKind.claude.resumeCommand(sessionID: id) ?? "claude --resume"
        case (.claude, nil): base = "claude --resume"
        case let (.codex, id?): base = AgentKind.codex.resumeCommand(sessionID: id) ?? "codex resume"
        case (.codex, nil): base = "codex resume"
        }
        controller.view.send(txt: command(base, as: account) + "\n")
        return id.map { .resumed(id: $0) } ?? .openedPicker
    }
}

extension WorkspaceRuntime {
    /// Signs in to a new account: prepares its folder, runs the agent's login in a session of its
    /// own, and lists the account once the login succeeded. The session closes on success and
    /// stays open on failure, so its error can be read. Without shell integration there is no
    /// exit status to wait for: then, once `statusPollAfter` passes with no command seen to start,
    /// the new folder's sign-in is checked every `statusPollEvery` instead.
    public func addAccount(_ agent: AccountAgent, statusPollAfter: TimeInterval = 15,
                           statusPollEvery: TimeInterval = 3) async -> AddOutcome {
        guard let project = store.focusedSession?.projectID ?? store.state.orderedProjects.first?.id,
              let pending = try? accounts.beginAdd(agent) else { return .failed }
        let session = newSession(in: project)
        store.renameSession(session.id, to: "Sign in to \(agent.displayName)")
        guard let pane = layout(for: session.id).paneIDs.first else {
            closeSession(session.id)
            return await accounts.finishAdd(pending, loginSucceeded: false)   // discards the folder
        }
        let stream = bus.events()   // subscribed before the command is typed
        type(pending.loginCommand, intoPaneWhenReady: pane)
        open(session: session.id)
        // The login's exit status, or nil if the person closed the session first.
        let sessionID = session.id
        let result = LoginResult()
        let listener = Task { @MainActor in
            var started = false
            for await event in stream where event.sessionID == sessionID {
                if case .commandStarted = event.event { started = true; result.sawCommandStart = true }
                if started, case let .commandFinished(code) = event.event {
                    result.exitCode = code
                    result.finished = true
                    return
                }
            }
        }
        let began = Date()
        var lastPoll = Date.distantPast
        while !result.finished, store.state.sessions.contains(where: { $0.id == sessionID }) {
            try? await Task.sleep(for: .milliseconds(200))
            let now = Date()
            if !result.sawCommandStart, now.timeIntervalSince(began) >= statusPollAfter, now.timeIntervalSince(lastPoll) >= statusPollEvery {
                lastPoll = now
                if await accounts.hasSignedIn(pending), !result.finished {
                    result.exitCode = 0
                    result.finished = true
                }
            }
        }
        listener.cancel()
        let exitCode = result.finished ? result.exitCode : nil
        let outcome = await accounts.finishAdd(pending, loginSucceeded: exitCode == 0)
        if case .failed = outcome {} else { closeSession(session.id) }
        return outcome
    }
}

/// Where the sign-in's exit status lands while `addAccount` waits.
@MainActor private final class LoginResult {
    var finished = false
    /// Shell integration reported the command starting, so its exit status will come.
    var sawCommandStart = false
    var exitCode: Int?
}
