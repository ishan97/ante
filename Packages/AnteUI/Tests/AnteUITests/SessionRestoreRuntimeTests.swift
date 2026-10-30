// Packages/AnteUI/Tests/AnteUITests/SessionRestoreRuntimeTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class SessionRestoreRuntimeTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-rs-\(UUID().uuidString)")
        paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func config(restore: Bool) -> AnteConfig {
        var config = AnteConfig.default
        config.sessions.restore = restore
        return config
    }

    private func makeRuntime(restore: Bool, script: String = "sleep 30") -> WorkspaceRuntime {
        WorkspaceRuntime(paths: paths, config: config(restore: restore), launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRestoreBringsBackSessionsSplitsFoldersAndFocus() throws {
        let work = try makeFolder("work")
        let runtime = makeRuntime(restore: true)
        let project = runtime.store.addProject(rootDirectory: work)
        let a = runtime.store.focusedSession!
        runtime.open(session: a.id)
        runtime.splitFocusedPane(axis: .horizontal)
        runtime.setRatio(0.3, forSplitContaining: runtime.focusedPaneID!)
        runtime.store.renameSession(a.id, to: "Split one")
        let b = runtime.newSession(in: project.id)
        runtime.open(session: a.id)
        runtime.prepareForQuit()
        XCTAssertEqual(StateStore(paths: paths).load().state.sessions.count, 2, "sessions stay in the state file")
        XCTAssertTrue(AnteSessionHistoryStore(paths: paths).all().isEmpty, "nothing is filed: it all comes back")

        let relaunched = makeRuntime(restore: true)
        defer { relaunched.prepareForQuit() }
        XCTAssertEqual(relaunched.store.allVisibleSessions.map(\.id), [a.id, b.id])
        XCTAssertEqual(relaunched.store.allVisibleSessions.first?.name, "Split one")
        XCTAssertEqual(relaunched.store.state.focusedSessionID, a.id)
        guard case let .split(axis, ratio, _, _)? = relaunched.existingLayout(for: a.id) else {
            return XCTFail("the split comes back")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 0.3, accuracy: 0.0001)
        XCTAssertTrue(relaunched.existingLayout(for: a.id)!.contains(relaunched.focusedPaneID!), "the focused session has keyboard focus")
        let bPane = try XCTUnwrap(relaunched.existingLayout(for: b.id)?.paneIDs.first, "every session is live at once")
        XCTAssertEqual(relaunched.controller(for: bPane).currentDirectory?.path, work.path)
        XCTAssertEqual(relaunched.controller(for: bPane).state, .running)
    }

    func testTurningRestoreOffStartsFreshAgain() {
        let runtime = makeRuntime(restore: true)
        let kept = runtime.store.focusedSession!
        runtime.open(session: kept.id)
        runtime.prepareForQuit()

        let relaunched = makeRuntime(restore: false)
        defer { relaunched.prepareForQuit() }
        XCTAssertEqual(relaunched.store.allVisibleSessions.count, 1)
        XCTAssertNotEqual(relaunched.store.allVisibleSessions.first?.id, kept.id)
    }

    func testAMissingFolderFallsBackToTheProjectAndResumesNothing() throws {
        let work = try makeFolder("work")
        let project = Project(name: "work", rootDirectory: work)
        let gone = work.appendingPathComponent("deleted-branch")
        let session = Session(projectID: project.id, name: "Agent", workingDirectory: gone,
                              layout: .pane(SavedPane(workingDirectory: gone, agent: .claude)))
        try StateStore(paths: paths).save(AppState(projects: [project], sessions: [session], focusedSessionID: session.id))

        let runtime = makeRuntime(restore: true)
        defer { runtime.prepareForQuit() }
        let pane = try XCTUnwrap(runtime.existingLayout(for: session.id)?.paneIDs.first)
        XCTAssertEqual(runtime.controller(for: pane).currentDirectory, work)
        XCTAssertTrue(runtime.pendingPaneCommands.isEmpty, "“continue the latest” in another folder would open the wrong conversation")
    }

    func testAnAgentPaneGetsItsResumeCommandAtTheFirstPrompt() async throws {
        let work = try makeFolder("work")
        let project = Project(name: "work", rootDirectory: work)
        let id = "0f4b2c9e-1111-2222-3333-444455556666"
        let session = Session(projectID: project.id, name: "Agent", workingDirectory: work,
                              layout: .split(.vertical, ratio: 0.5,
                                             first: .pane(SavedPane(workingDirectory: work)),
                                             second: .pane(SavedPane(workingDirectory: work, agent: .claude, agentSessionID: id))))
        try StateStore(paths: paths).save(AppState(projects: [project], sessions: [session], focusedSessionID: session.id))

        // Draws a prompt (OSC 133;A), then writes the first line it is sent to a file named after the pane.
        let script = #"printf '\033]133;A\007'; IFS= read -r line; printf '%s' "$line" > "typed-$$.txt"; sleep 30"#
        let runtime = makeRuntime(restore: true, script: script)
        defer { runtime.prepareForQuit() }
        XCTAssertEqual(runtime.pendingPaneCommands.count, 1, "only the agent pane gets a command")
        let deadline = Date().addingTimeInterval(5)
        var typed: [String] = []
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? []
            typed = files.filter { $0.hasPrefix("typed-") }
                .compactMap { try? String(contentsOf: work.appendingPathComponent($0), encoding: .utf8) }
            if !typed.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(typed, ["claude --resume \(id)"])
        XCTAssertTrue(runtime.pendingPaneCommands.isEmpty)
    }

    func testQuitWithRestoreRecordsTheAgentAndCloseForgetsThePane() throws {
        let runtime = makeRuntime(restore: true)
        let session = runtime.store.focusedSession!
        runtime.open(session: session.id)
        runtime.splitFocusedPane(axis: .vertical)
        XCTAssertEqual(runtime.store.focusedSession?.layout?.panes.count, 2, "recorded as it changes, so a crash restores too")
        runtime.closeFocusedPane()
        XCTAssertEqual(runtime.store.focusedSession?.layout?.panes.count, 1)
        runtime.prepareForQuit()
        runtime.prepareForQuit()
        XCTAssertEqual(StateStore(paths: paths).load().state.sessions.first?.layout?.panes.count, 1, "a second call changes nothing")
    }

    func testWhichConversationAnAgentPaneComesBackTo() {
        let folder = URL(fileURLWithPath: "/tmp/repo")
        let started = "0f4b2c9e-1111-2222-3333-444455556666", hooked = "aaaaaaaa-1111-2222-3333-444455556666"
        func pane(_ commandLine: [String], hook: String?, shares: Bool) -> SavedPane {
            WorkspaceRuntime.savedAgentPane(agent: .claude, directory: folder, commandLine: commandLine, hookSessionID: hook, sharesFolder: shares)
        }
        XCTAssertEqual(pane(["claude", "--resume", started], hook: hooked, shares: false).agentSessionID, started,
                       "the id it was started with is this pane's for certain; a hook may be another Claude in the folder")
        XCTAssertEqual(pane(["claude"], hook: hooked, shares: false).agentSessionID, hooked)
        XCTAssertNil(pane(["claude"], hook: hooked, shares: true).agentSessionID, "a hook names only the folder")
        XCTAssertEqual(pane(["claude"], hook: nil, shares: false).resumeCommand, "claude --continue")
        XCTAssertEqual(pane(["claude"], hook: hooked, shares: true).resumeCommand, "claude --resume",
                       "two Claude panes in one folder never both continue the latest conversation")
        XCTAssertEqual(pane(["claude", "-r", started], hook: nil, shares: true).resumeCommand, "claude --resume \(started)")
    }

    func testTurningRestoreOffFilesSavedAgentSessionsIntoHistory() throws {
        let work = try makeFolder("work")
        let project = Project(name: "work", rootDirectory: work)
        let agentSession = Session(projectID: project.id, name: "Fix login", workingDirectory: work,
                                   layout: .split(.horizontal, ratio: 0.5,
                                                  first: .pane(SavedPane(workingDirectory: work)),
                                                  second: .pane(SavedPane(workingDirectory: work, agent: .codex))))
        let shellSession = Session(projectID: project.id, name: "Shell", workingDirectory: work, order: 1,
                                   layout: .pane(SavedPane(workingDirectory: work)))
        try StateStore(paths: paths).save(AppState(projects: [project], sessions: [agentSession, shellSession]))

        let runtime = makeRuntime(restore: false)
        defer { runtime.prepareForQuit() }
        let history = AnteSessionHistoryStore(paths: paths).all()
        XCTAssertEqual(history.map(\.name), ["Fix login"], "the agent session is filed; the shell has nothing to resume")
        XCTAssertEqual(history.first?.agent, .codex)
        XCTAssertEqual(runtime.store.allVisibleSessions.count, 1, "and the launch starts fresh")
    }

    // MARK: - New folder

    func testNewFolderRequestsAnchorWhereTheyWereAskedFor() throws {
        let parent = try makeFolder("code")
        let runtime = makeRuntime(restore: false)
        defer { runtime.prepareForQuit() }
        let project = runtime.store.addProject(rootDirectory: parent)
        runtime.showNewFolder(inside: project)
        XCTAssertEqual(runtime.newFolder?.parent, parent)
        XCTAssertEqual(runtime.newFolder?.anchor, project.id)
        runtime.showNewFolder()
        XCTAssertNil(runtime.newFolder?.anchor, "the footer button")
        XCTAssertEqual(runtime.newFolder?.parent.path, root.path, "beside the latest project")
        XCTAssertEqual(runtime.newFolder?.name, "")
    }

    func testCreateProjectFolderMakesTheFolderAddsAProjectAndOpensASession() throws {
        let parent = try makeFolder("code")
        let runtime = makeRuntime(restore: false)
        defer { runtime.prepareForQuit() }
        let project = try runtime.createProjectFolder(named: "  new-app ", in: parent)
        let folder = parent.appendingPathComponent("new-app")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        XCTAssertEqual(project.name, "new-app")
        XCTAssertEqual(project.rootDirectory.path, folder.path)
        XCTAssertEqual(runtime.store.focusedSession?.projectID, project.id, "a session opens in it")
        XCTAssertEqual(runtime.defaultNewFolderParent.path, parent.path, "the next one goes beside it")

        XCTAssertThrowsError(try runtime.createProjectFolder(named: "new-app", in: parent)) {
            XCTAssertEqual($0 as? WorkspaceRuntime.NewFolderError, .alreadyExists("new-app"))
        }
        XCTAssertThrowsError(try runtime.createProjectFolder(named: "   ", in: parent)) {
            XCTAssertEqual($0 as? WorkspaceRuntime.NewFolderError, .emptyName)
        }
        for bad in ["a/b", "a:b", ".", ".."] {
            XCTAssertThrowsError(try runtime.createProjectFolder(named: bad, in: parent)) {
                XCTAssertEqual($0 as? WorkspaceRuntime.NewFolderError, .invalidName, bad)
            }
        }
        XCTAssertThrowsError(try runtime.createProjectFolder(named: "x", in: parent.appendingPathComponent("missing"))) {
            guard case .noParent? = $0 as? WorkspaceRuntime.NewFolderError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(runtime.store.state.projects.count, 2, "failures add nothing")
    }

    func testNewFoldersGoHomeUntilThereIsAProject() {
        let runtime = makeRuntime(restore: false)
        defer { runtime.prepareForQuit() }
        XCTAssertEqual(runtime.defaultNewFolderParent.path, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
    }

    func testSettingsToggleWritesTheSessionsSection() throws {
        let runtime = makeRuntime(restore: false)
        defer { runtime.prepareForQuit() }
        let model = SettingsModel(runtime: runtime)
        XCTAssertFalse(model.restoreSessions)
        model.restoreSessions = true
        XCTAssertTrue(model.restoreSessions, "shows at once")
        model.flushPendingWrites()
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertTrue(text.contains("[sessions]\nrestore = true"), text)
        XCTAssertTrue(try ConfigLoader().load(from: paths.configFile).config.sessions.restore)
    }
}
