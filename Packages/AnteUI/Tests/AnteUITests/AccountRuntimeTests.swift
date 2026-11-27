import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

/// Accounts in the running workspace: panes know their account, agents start as an account,
/// restore and resume ask, and a live conversation moves to another account.
@MainActor
final class AccountRuntimeTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!
    private var cli: FakeAgentCLI!
    private var launchedPanes: [PaneID] = []
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("ante-acct-rt-\(UUID().uuidString)")
        paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
        try fm.createDirectory(at: paths.home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        cli = FakeAgentCLI()
        launchedPanes = []
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    /// A runtime whose panes run `script`, recording which pane each shell was made for.
    func makeRuntime(script: String, accounts: AccountsModel? = nil, config: AnteConfig = .default) -> WorkspaceRuntime {
        let model = accounts ?? AccountsModel(paths: paths.accountPaths, cli: cli)
        return WorkspaceRuntime(paths: paths, config: config, accounts: model) { [weak self] _, pane in
            self?.launchedPanes.append(pane)
            return ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        }
    }

    func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// What the stand-in shell received; nil until a line arrived (`> file` creates it empty at once).
    func text(_ url: URL) -> String? {
        let line = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return line?.isEmpty == false ? line : nil
    }

    /// Two Claude accounts: the default-folder login and a folder account "k3x9q2m7".
    func twoAccounts() throws -> (AccountsModel, personal: AgentAccount, work: AgentAccount) {
        let personal = AgentAccount(id: "default", agent: .claude, name: "Personal", email: "p@x", org: nil, plan: "Max", isDefaultFolder: true)
        let work = AgentAccount(id: "k3x9q2m7", agent: .claude, name: "Work", email: "w@x", org: nil, plan: "Pro", isDefaultFolder: false)
        try AccountStore(paths: paths.accountPaths).save([personal, work])
        return (AccountsModel(paths: paths.accountPaths, cli: cli), personal, work)
    }

    /// An ad-hoc-signed `sleep` named `name` (macOS hides the environment of Apple's binaries).
    func ownBinary(named name: String, from source: String = "/bin/sleep") throws -> URL {
        let dir = root.appendingPathComponent("bin-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(name)
        try fm.copyItem(at: URL(fileURLWithPath: source), to: copy)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["-f", "-s", "-", copy.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        return copy
    }

    // MARK: - Task 8

    func testFactoryGetsPaneID() {
        let runtime = makeRuntime(script: "sleep 5")
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        XCTAssertEqual(launchedPanes.last, runtime.layout(for: session).paneIDs.first)
    }

    func testStartAgentTypesAccountCommand() async throws {
        let (accounts, _, work) = try twoAccounts()
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: "printf '\\033]133;A\\007$ '; head -n 1 > '\(typed.path)'", accounts: accounts)
        defer { runtime.prepareForQuit() }
        runtime.startAgent(.claude, account: work, inNewSessionOf: runtime.store.state.projects[0].id)
        await waitUntil { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "CLAUDE_CONFIG_DIR=\(work.folder(in: paths.accountPaths).path) claude")
    }

    func testAccountInPaneAndSavedPaneRecordIt() async throws {
        let (accounts, _, work) = try twoAccounts()
        let claude = try ownBinary(named: "claude")
        let folder = work.folder(in: paths.accountPaths).path
        let runtime = makeRuntime(script: "CLAUDE_CONFIG_DIR='\(folder)' exec '\(claude.path)' 30", accounts: accounts)
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        let pane = runtime.layout(for: session).paneIDs[0]
        await waitUntil {
            runtime.controller(for: pane).probeNow()
            return runtime.controller(for: pane).agent == .claude
        }
        XCTAssertEqual(runtime.account(in: pane)?.id, "k3x9q2m7")
        XCTAssertEqual(runtime.savedPane(pane).accountID, "k3x9q2m7")
    }

    func testAccountInPaneIsNilForAShell() {
        let runtime = makeRuntime(script: "sleep 5")
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        XCTAssertNil(runtime.account(in: runtime.layout(for: session).paneIDs[0]))
    }

    // MARK: - Task 9: restore and resume ask which account

    private let conversation = "3c2b69dc-f7ea-490e-878b-f85b72bbb5ff"

    private func restoreConfig() -> AnteConfig {
        var config = AnteConfig.default
        config.sessions.restore = true
        return config
    }

    /// Leaves a state file with one session whose pane ran Claude as `accountID` in `folder`.
    private func seedRestoredClaudePane(folder: URL, accountID: String?) throws {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = makeRuntime(script: "sleep 30", config: restoreConfig())
        let session = first.store.focusedSession!.id
        first.prepareForQuit()
        first.store.setLayout(.pane(SavedPane(workingDirectory: folder, agent: .claude, agentSessionID: conversation, accountID: accountID)),
                              for: session)
        first.store.saveNow()
    }

    private func typingScript(_ typed: URL) -> String { "printf '\\033]133;A\\007$ '; head -n 1 > '\(typed.path)'" }

    func testRestoreWithDefaultTypesImmediately() async throws {
        let (accounts, _, work) = try twoAccounts()
        accounts.setDefault(work, for: .claude)
        let folder = root.appendingPathComponent("proj")
        try seedRestoredClaudePane(folder: folder, accountID: "default")
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: typingScript(typed), accounts: accounts, config: restoreConfig())
        defer { runtime.prepareForQuit() }
        XCTAssertEqual(runtime.pendingRestores, [])
        await waitUntil { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "CLAUDE_CONFIG_DIR=\(work.folder(in: paths.accountPaths).path) claude --resume \(conversation)")
    }

    func testRestoreWithoutDefaultQueuesItems() async throws {
        let (accounts, _, work) = try twoAccounts()
        let folder = root.appendingPathComponent("proj")
        try seedRestoredClaudePane(folder: folder, accountID: "k3x9q2m7")
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: typingScript(typed), accounts: accounts, config: restoreConfig())
        defer { runtime.prepareForQuit() }
        XCTAssertEqual(runtime.pendingRestores.count, 1)
        XCTAssertEqual(runtime.pendingRestores.first?.preselected, work)
        XCTAssertEqual(runtime.pendingRestores.first?.agent, .claude)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(text(typed), "nothing typed until the person chooses")
    }

    func testConfirmRestoreTypesChosenAccount() async throws {
        let (accounts, personal, _) = try twoAccounts()
        try seedRestoredClaudePane(folder: root.appendingPathComponent("proj"), accountID: "k3x9q2m7")
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: typingScript(typed), accounts: accounts, config: restoreConfig())
        defer { runtime.prepareForQuit() }
        let item = try XCTUnwrap(runtime.pendingRestores.first)
        try await Task.sleep(for: .milliseconds(400))   // the prompt has long been drawn when the person answers
        runtime.confirmRestore([item.pane: personal])
        XCTAssertEqual(runtime.pendingRestores, [])
        await waitUntil(3) { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "ANTE_ACCOUNT=default claude --resume \(conversation)")
    }

    func testSkipRestoreLeavesShells() async throws {
        let (accounts, _, _) = try twoAccounts()
        try seedRestoredClaudePane(folder: root.appendingPathComponent("proj"), accountID: nil)
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: typingScript(typed), accounts: accounts, config: restoreConfig())
        defer { runtime.prepareForQuit() }
        runtime.skipRestoreAgents()
        XCTAssertEqual(runtime.pendingRestores, [])
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(text(typed))
    }

    func testResumeWithAccountTypesPrefixedCommand() async throws {
        let (accounts, _, work) = try twoAccounts()
        let typed = root.appendingPathComponent("typed")
        let runtime = makeRuntime(script: typingScript(typed), accounts: accounts)
        defer { runtime.prepareForQuit() }
        let past = PastSession(id: conversation, agent: .claude, title: "Fix login", projectPath: root.path, createdAt: Date(),
                               modifiedAt: Date(), resumeCommand: AgentKind.claude.resumeCommand(sessionID: conversation))
        runtime.resume(past, account: work)
        await waitUntil { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "CLAUDE_CONFIG_DIR=\(work.folder(in: paths.accountPaths).path) claude --resume \(conversation)")
    }

    func testResumeFocusesPaneAlreadyRunningConversation() async throws {
        let (accounts, _, work) = try twoAccounts()
        let claude = try ownBinary(named: "claude")
        let folder = work.folder(in: paths.accountPaths)
        let runtime = makeRuntime(script: "CLAUDE_CONFIG_DIR='\(folder.path)' exec '\(claude.path)' 30", accounts: accounts)
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        let pane = runtime.layout(for: session).paneIDs[0]
        await waitUntil {
            runtime.controller(for: pane).probeNow()
            return runtime.controller(for: pane).agent == .claude
        }
        let pid = try XCTUnwrap(runtime.controller(for: pane).foreground?.pid)
        try fm.createDirectory(at: folder.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data(#"{"sessionId":"ID","status":"idle"}"#.replacingOccurrences(of: "ID", with: conversation).utf8)
            .write(to: folder.appendingPathComponent("sessions/\(pid).json"))
        let other = runtime.newSession(in: runtime.store.state.projects[0].id)
        runtime.open(session: other.id)
        let before = runtime.store.allVisibleSessions.count
        let past = PastSession(id: conversation, agent: .claude, title: "x", projectPath: root.path, createdAt: Date(), modifiedAt: Date(),
                               resumeCommand: AgentKind.claude.resumeCommand(sessionID: conversation))
        XCTAssertEqual(runtime.paneRunning(conversation: conversation, agent: .claude), pane)
        runtime.resume(past, account: nil)
        XCTAssertEqual(runtime.store.allVisibleSessions.count, before, "no second writer")
        XCTAssertEqual(runtime.focusedPaneID, pane)
        // The same conversation from Ante's own closed-session history (row id `ante-<uuid>`).
        runtime.focusPane(runtime.layout(for: other.id).paneIDs[0])
        let closed = ClosedSession(name: "x", workingDirectory: root.path, projectPath: root.path, lastCommand: nil, agent: .claude,
                                   agentSessionID: conversation)
        runtime.resume(closed.asPastSession, account: nil)
        XCTAssertEqual(runtime.store.allVisibleSessions.count, before, "no second writer from a history row either")
        XCTAssertEqual(runtime.focusedPaneID, pane)
    }

    /// No live-process file and no hook: the id on the command line still marks it open.
    func testResumeFocusesPaneStartedWithThatConversation() async throws {
        let (accounts, _, _) = try twoAccounts()
        // A shell named claude that stays up with `--resume <id>` on its command line.
        let claude = try ownBinary(named: "claude", from: "/bin/bash")
        let runtime = makeRuntime(script: "exec '\(claude.path)' -c 'sleep 30; :' --resume \(conversation)", accounts: accounts)
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        let pane = runtime.layout(for: session).paneIDs[0]
        await waitUntil {
            runtime.controller(for: pane).probeNow()
            return runtime.controller(for: pane).agent == .claude
        }
        XCTAssertNil(runtime.liveConversation(in: pane).id)
        XCTAssertEqual(runtime.paneRunning(conversation: conversation, agent: .claude), pane)
        XCTAssertNil(runtime.paneRunning(conversation: "3c2b69dc-0000-0000-0000-000000000000", agent: .claude))
    }

    // MARK: - Task 10: switching a live conversation

    /// A pane whose stand-in `claude` runs as `account` until Ctrl-C (or forever with
    /// `ignoreInterrupt`), then a prompt, then records the next line typed.
    private func paneRunningClaude(as account: AgentAccount, accounts: AccountsModel, typed: URL,
                                   ignoreInterrupt: Bool = false) async throws -> (WorkspaceRuntime, PaneID, pid_t) {
        let claude = try ownBinary(named: "claude")
        let variable = account.isDefaultFolder ? "" : "CLAUDE_CONFIG_DIR='\(account.folder(in: paths.accountPaths).path)' "
        let trap = ignoreInterrupt ? "trap '' INT" : "trap ':' INT"
        // Job control, as in an interactive shell: the agent gets its own process group, so it is
        // the pane's foreground process and Ctrl-C reaches only it.
        let script = "set -m; \(trap); printf '\\033]133;A\\007$ '; printf '\\033]133;C\\007'; \(variable)'\(claude.path)' 30; "
            // The shell itself reads the next line, as at a real prompt (no other process in front).
            + "printf '\\033]133;D;0\\007\\033]133;A\\007$ '; IFS= read -r line; printf '%s\\n' \"$line\" > '\(typed.path)'"
        let runtime = makeRuntime(script: script, accounts: accounts)
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        let pane = runtime.layout(for: session).paneIDs[0]
        await waitUntil {
            runtime.controller(for: pane).probeNow()
            return runtime.controller(for: pane).agent == .claude
        }
        let pid = try XCTUnwrap(runtime.controller(for: pane).foreground?.pid)
        return (runtime, pane, pid)
    }

    private func writeRegistry(folder: URL, pid: pid_t, id: String, status: String = "idle") throws {
        try fm.createDirectory(at: folder.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data(#"{"sessionId":"ID","status":"S"}"#.replacingOccurrences(of: "ID", with: id).replacingOccurrences(of: "S", with: status).utf8)
            .write(to: folder.appendingPathComponent("sessions/\(pid).json"))
    }

    func testConversationIDPrefersRegistry() async throws {
        let (accounts, _, work) = try twoAccounts()
        let (runtime, pane, pid) = try await paneRunningClaude(as: work, accounts: accounts, typed: root.appendingPathComponent("t"))
        defer { runtime.prepareForQuit() }
        runtime.board.ingest([HookEvent(agent: .claude, sessionID: "from-hook-1", cwd: "/x", event: "SessionStart", meaning: .other,
                                        at: Date(), paneID: pane.rawValue.uuidString)])
        try writeRegistry(folder: work.folder(in: paths.accountPaths), pid: pid, id: "from-registry-1", status: "busy")
        let live = runtime.liveConversation(in: pane)
        XCTAssertEqual(live.id, "from-registry-1")
        XCTAssertTrue(live.isBusy)
    }

    func testConversationIDFallsBackToPaneHook() async throws {
        let (accounts, _, work) = try twoAccounts()
        let (runtime, pane, _) = try await paneRunningClaude(as: work, accounts: accounts, typed: root.appendingPathComponent("t"))
        defer { runtime.prepareForQuit() }
        runtime.board.ingest([HookEvent(agent: .claude, sessionID: "from-hook-1", cwd: "/x", event: "SessionStart", meaning: .other,
                                        at: Date(), paneID: pane.rawValue.uuidString),
                              HookEvent(agent: .claude, sessionID: "other-pane-1", cwd: "/x", event: "SessionStart", meaning: .other,
                                        at: Date(), paneID: PaneID().rawValue.uuidString)])
        XCTAssertEqual(runtime.liveConversation(in: pane).id, "from-hook-1")
    }

    func testSwitchTypesResumeForNewAccount() async throws {
        let (accounts, personal, work) = try twoAccounts()
        let typed = root.appendingPathComponent("typed")
        let (runtime, pane, pid) = try await paneRunningClaude(as: work, accounts: accounts, typed: typed)
        defer { runtime.prepareForQuit() }
        try writeRegistry(folder: work.folder(in: paths.accountPaths), pid: pid, id: conversation)
        let outcome = await runtime.switchAccount(pane: pane, to: personal)
        XCTAssertEqual(outcome, .resumed(id: conversation))
        await waitUntil { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "ANTE_ACCOUNT=default claude --resume \(conversation)")
        XCTAssertEqual(kill(pid, 0), -1, "the old process is gone before the new one starts")
    }

    func testSwitchWithoutIDOpensPicker() async throws {
        let (accounts, personal, work) = try twoAccounts()
        let typed = root.appendingPathComponent("typed")
        let (runtime, pane, _) = try await paneRunningClaude(as: personal, accounts: accounts, typed: typed)
        defer { runtime.prepareForQuit() }
        let outcome = await runtime.switchAccount(pane: pane, to: work)
        XCTAssertEqual(outcome, .openedPicker)
        await waitUntil { self.text(typed) != nil }
        XCTAssertEqual(text(typed), "CLAUDE_CONFIG_DIR=\(work.folder(in: paths.accountPaths).path) claude --resume")
    }

    func testSwitchTimesOutWithoutTyping() async throws {
        let (accounts, personal, work) = try twoAccounts()
        let typed = root.appendingPathComponent("typed")
        let (runtime, pane, pid) = try await paneRunningClaude(as: work, accounts: accounts, typed: typed, ignoreInterrupt: true)
        defer { runtime.prepareForQuit(); kill(pid, SIGKILL) }
        try writeRegistry(folder: work.folder(in: paths.accountPaths), pid: pid, id: conversation)
        let outcome = await runtime.switchAccount(pane: pane, to: personal, timeout: 1.5)
        XCTAssertEqual(outcome, .cancelled)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(text(typed))
    }

    func testSwitchToSameAccountDoesNothing() async throws {
        let (accounts, _, work) = try twoAccounts()
        let (runtime, pane, pid) = try await paneRunningClaude(as: work, accounts: accounts, typed: root.appendingPathComponent("t"))
        defer { runtime.prepareForQuit() }
        let outcome = await runtime.switchAccount(pane: pane, to: work)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(kill(pid, 0), 0, "still running")
    }

    func testSavedPanePrefersTheLiveConversationOverTheCommandLine() {
        // `claude --resume old` followed by /clear: the live id wins, even when another pane shares the folder.
        let saved = WorkspaceRuntime.savedAgentPane(agent: .claude, directory: root, commandLine: ["claude", "--resume", "old-session-1"],
                                                    liveSessionID: "new-session-1", hookSessionID: nil, sharesFolder: true)
        XCTAssertEqual(saved.agentSessionID, "new-session-1")
        let fallback = WorkspaceRuntime.savedAgentPane(agent: .claude, directory: root, commandLine: ["claude", "--resume", "old-session-1"],
                                                       liveSessionID: nil, hookSessionID: nil, sharesFolder: true)
        XCTAssertEqual(fallback.agentSessionID, "old-session-1")
    }

    // MARK: - Task 11: adding an account

    /// A stand-in shell: prompt, record the typed line, report it finished with `exitCode`.
    private func loginShell(_ typed: URL, exitCode: Int) -> String {
        "printf '\\033]133;A\\007$ '; head -n 1 > '\(typed.path)'; printf '\\033]133;C\\007'; "
            + "printf '\\033]133;D;\(exitCode)\\007\\033]133;A\\007$ '; sleep 30"
    }

    func testAddAccountFlowSucceeds() async throws {
        let typed = root.appendingPathComponent("typed")
        cli.fallback = AgentStatus(loggedIn: true, email: "new@x.com", org: nil, plan: "Pro", isSubscription: true)
        let accounts = AccountsModel(paths: paths.accountPaths, cli: cli)
        let runtime = makeRuntime(script: loginShell(typed, exitCode: 0), accounts: accounts)
        defer { runtime.prepareForQuit() }
        let sessionsBefore = runtime.store.allVisibleSessions.count
        let outcome = await runtime.addAccount(.claude)
        guard case let .added(account) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(account.email, "new@x.com")
        XCTAssertEqual(text(typed), "CLAUDE_CONFIG_DIR=\(account.folder(in: paths.accountPaths).path) claude auth login")
        XCTAssertEqual(accounts.accounts(for: .claude).map(\.id), [account.id])
        XCTAssertEqual(runtime.store.allVisibleSessions.count, sessionsBefore, "the sign-in session closes")
    }

    func testAddAccountFlowFailureDiscards() async throws {
        let typed = root.appendingPathComponent("typed")
        let accounts = AccountsModel(paths: paths.accountPaths, cli: cli)
        let runtime = makeRuntime(script: loginShell(typed, exitCode: 1), accounts: accounts)
        defer { runtime.prepareForQuit() }
        let sessionsBefore = runtime.store.allVisibleSessions.count
        let outcome = await runtime.addAccount(.claude)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(accounts.accounts, [])
        let folders = (try? fm.contentsOfDirectory(atPath: paths.accountPaths.root.appendingPathComponent("claude").path)) ?? []
        XCTAssertEqual(folders, [], "the half-made folder is gone")
        XCTAssertEqual(runtime.store.allVisibleSessions.count, sessionsBefore + 1, "left open so the error stays readable")
    }

    /// No shell integration: no command start or exit status ever arrives. The sign-in is noticed
    /// from the folder's own status instead.
    func testAddAccountWithoutShellIntegrationNoticesTheSignIn() async throws {
        let typed = root.appendingPathComponent("typed")
        cli.fallback = AgentStatus(loggedIn: true, email: "plain@x.com", org: nil, plan: nil, isSubscription: true)
        let accounts = AccountsModel(paths: paths.accountPaths, cli: cli)
        let runtime = makeRuntime(script: "printf '$ '; head -n 1 > '\(typed.path)'; sleep 30", accounts: accounts)
        defer { runtime.prepareForQuit() }
        let sessionsBefore = runtime.store.allVisibleSessions.count
        let outcome = await runtime.addAccount(.claude, statusPollAfter: 0.5, statusPollEvery: 0.3)
        guard case let .added(account) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(account.email, "plain@x.com")
        XCTAssertEqual(runtime.store.allVisibleSessions.count, sessionsBefore, "the sign-in session closes")
    }

    func testAddAccountClosingTheSignInSessionDiscards() async throws {
        let accounts = AccountsModel(paths: paths.accountPaths, cli: cli)
        let runtime = makeRuntime(script: "printf '\\033]133;A\\007$ '; sleep 30", accounts: accounts)
        defer { runtime.prepareForQuit() }
        let adding = Task { await runtime.addAccount(.claude) }
        try await Task.sleep(for: .milliseconds(500))
        let signIn = try XCTUnwrap(runtime.store.allVisibleSessions.first { $0.name.hasPrefix("Sign in") })
        let closedAt = Date()
        runtime.closeSession(signIn.id)
        let safety = Task { try await Task.sleep(for: .seconds(8)); adding.cancel() }
        let outcome = await adding.value
        safety.cancel()
        XCTAssertLessThan(Date().timeIntervalSince(closedAt), 3, "noticed the closed session itself")
        XCTAssertEqual(outcome, .failed)
        let folders = (try? fm.contentsOfDirectory(atPath: paths.accountPaths.root.appendingPathComponent("claude").path)) ?? []
        XCTAssertEqual(folders, [])
    }
}
