// Packages/AnteCore/Tests/AnteCoreTests/SessionRestoreTests.swift
import XCTest
@testable import AnteCore

@MainActor
final class SessionRestoreTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUp() {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ante-restore-\(UUID().uuidString)")
        paths = AppPaths(root: tempRoot.appendingPathComponent("state"), configRoot: tempRoot.appendingPathComponent("config"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testSessionsConfigDefaultsOffAndParses() throws {
        XCTAssertFalse(AnteConfig.default.sessions.restore, "a launch starts fresh unless asked")
        XCTAssertTrue(try ConfigLoader().parse("[sessions]\nrestore = true\n").sessions.restore)
        XCTAssertFalse(try ConfigLoader().parse("[sessions]\n").sessions.restore)
    }

    func testContinueCommandsAndIdsFromTheCommandLine() {
        XCTAssertEqual(AgentKind.claude.continueCommand, "claude --continue")
        XCTAssertEqual(AgentKind.codex.continueCommand, "codex resume --last")
        XCTAssertEqual(AgentKind.opencode.continueCommand, "opencode --continue")
        XCTAssertEqual(AgentKind.pi.continueCommand, "pi --continue")
        XCTAssertNil(AgentKind.aider.continueCommand)
        XCTAssertNil(AgentKind.shell.continueCommand)

        let id = "0f4b2c9e-1111-2222-3333-444455556666"
        XCTAssertEqual(AgentKind.claude.sessionID(fromCommandLine: ["node", "/opt/node_modules/@anthropic-ai/claude-code/cli.js", "--resume", id]), id)
        XCTAssertEqual(AgentKind.claude.sessionID(fromCommandLine: ["claude", "-r", id]), id)
        XCTAssertEqual(AgentKind.claude.sessionID(fromCommandLine: ["claude", "--resume=\(id)"]), id)
        XCTAssertNil(AgentKind.claude.sessionID(fromCommandLine: ["claude"]), "a new session has no id yet")
        XCTAssertNil(AgentKind.claude.sessionID(fromCommandLine: ["claude", "--resume", "x; rm -rf ~"]), "only safe tokens")
        XCTAssertEqual(AgentKind.codex.sessionID(fromCommandLine: ["codex", "resume", id]), id)
        XCTAssertNil(AgentKind.codex.sessionID(fromCommandLine: ["codex", "resume", "--last"]))
        XCTAssertEqual(AgentKind.opencode.sessionID(fromCommandLine: ["opencode", "-s", "ses_abcdefgh123"]), "ses_abcdefgh123")
        XCTAssertNil(AgentKind.aider.sessionID(fromCommandLine: ["aider", "--resume", id]))
        XCTAssertNil(AgentKind.claude.sessionID(fromCommandLine: ["claude", "--resume", "--dangerously-skip-permissions"]),
                     "the next flag is not an id")
        XCTAssertEqual(AgentKind.claude.pickerCommand, "claude --resume")
        XCTAssertEqual(AgentKind.codex.pickerCommand, "codex resume")
        XCTAssertEqual(AgentKind.gemini.pickerCommand, "gemini", "no picker: a plain start beats an empty shell")
    }

    func testSavedPaneResumesTheExactSessionWhenKnownElseTheLatest() {
        let folder = URL(fileURLWithPath: "/tmp/p")
        let id = "0f4b2c9e-1111-2222-3333-444455556666"
        XCTAssertEqual(SavedPane(workingDirectory: folder, agent: .claude, agentSessionID: id).resumeCommand, "claude --resume \(id)")
        XCTAssertEqual(SavedPane(workingDirectory: folder, agent: .claude).resumeCommand, "claude --continue")
        XCTAssertEqual(SavedPane(workingDirectory: folder, agent: .codex, agentSessionID: "bad id").resumeCommand, "codex resume --last")
        XCTAssertNil(SavedPane(workingDirectory: folder, agent: .gemini).resumeCommand, "no resume flow: the shell opens in the folder")
        XCTAssertNil(SavedPane(workingDirectory: folder).resumeCommand)
        XCTAssertEqual(SavedPane(workingDirectory: folder, agent: .claude, mayContinueLatest: false).resumeCommand, "claude --resume",
                       "a folder shared with another Claude pane: the picker, never the same conversation twice")
        XCTAssertEqual(SavedPane(workingDirectory: folder, agent: .claude, agentSessionID: id, mayContinueLatest: false).resumeCommand,
                       "claude --resume \(id)", "a known id is still exact")
    }

    func testAPaneSavedBeforeMayContinueLatestDecodesAsContinuable() throws {
        let json = #"{"workingDirectory":"file:///tmp/p/","agent":"codex"}"#
        let pane = try JSONDecoder().decode(SavedPane.self, from: Data(json.utf8))
        XCTAssertTrue(pane.mayContinueLatest)
        XCTAssertEqual(pane.resumeCommand, "codex resume --last")
    }

    func testLayoutRoundTripsThroughTheStateFile() throws {
        let project = Project(name: "p", rootDirectory: URL(fileURLWithPath: "/p"))
        let layout = SavedLayout.split(.horizontal, ratio: 0.3,
                                       first: .pane(SavedPane(workingDirectory: URL(fileURLWithPath: "/p"), agent: .claude, agentSessionID: "abcdefgh-1")),
                                       second: .split(.vertical, ratio: 0.5,
                                                      first: .pane(SavedPane(workingDirectory: URL(fileURLWithPath: "/p/a"))),
                                                      second: .pane(SavedPane(workingDirectory: URL(fileURLWithPath: "/p/b")))))
        XCTAssertEqual(layout.panes.map(\.workingDirectory.path), ["/p", "/p/a", "/p/b"])
        let session = Session(projectID: project.id, name: "s", workingDirectory: project.rootDirectory,
                              createdAt: Date(timeIntervalSince1970: 1_757_400_000), layout: layout)
        var state = AppState.empty
        state.projects = [project]
        state.sessions = [session]
        try StateStore(paths: paths).save(state)
        XCTAssertEqual(StateStore(paths: paths).load().state, state)
    }

    func testALayoutThisBuildCannotReadIsDroppedNotTheSession() throws {
        let project = Project(name: "p", rootDirectory: URL(fileURLWithPath: "/p"))
        var state = AppState.empty
        state.projects = [project]
        state.sessions = [Session(projectID: project.id, name: "kept", workingDirectory: project.rootDirectory,
                                  layout: .pane(SavedPane(workingDirectory: project.rootDirectory, agent: .claude)))]
        try StateStore(paths: paths).save(state)
        // A newer Ante knows an agent this one does not.
        let text = try String(contentsOf: paths.stateFile, encoding: .utf8).replacingOccurrences(of: "\"claude\"", with: "\"future-agent\"")
        try Data(text.utf8).write(to: paths.stateFile)
        let loaded = StateStore(paths: paths).load()
        XCTAssertNil(loaded.notice, "not a corrupt file")
        XCTAssertEqual(loaded.state.sessions.map(\.name), ["kept"])
        XCTAssertNil(loaded.state.sessions.first?.layout)
    }

    func testSetLayoutSavesOnlyChanges() async throws {
        let store = WorkspaceStore(stateStore: StateStore(paths: paths), saveDelay: .milliseconds(20))
        let project = store.addProject(rootDirectory: URL(fileURLWithPath: "/p"))
        let session = store.addSession(in: project.id)
        let layout = SavedLayout.pane(SavedPane(workingDirectory: URL(fileURLWithPath: "/p")))
        store.setLayout(layout, for: session.id)
        await store.flushPendingSave()
        XCTAssertEqual(StateStore(paths: paths).load().state.sessions.first?.layout, layout)
        try FileManager.default.removeItem(at: paths.stateFile)
        store.setLayout(layout, for: session.id)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path), "an unchanged layout schedules no write")
    }
}
