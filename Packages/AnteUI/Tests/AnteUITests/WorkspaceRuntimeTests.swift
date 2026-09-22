// Packages/AnteUI/Tests/AnteUITests/WorkspaceRuntimeTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class WorkspaceRuntimeTests: XCTestCase {
    private var root: URL!
    private var paths: AppPaths!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-rt-\(UUID().uuidString)")
        paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A runtime whose shells are `/bin/sh -c 'sleep 30'` so tests never touch the user's zsh.
    private func makeRuntime() -> WorkspaceRuntime {
        WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
    }

    func testFirstLaunchCreatesHomeProjectWithOneSession() {
        let runtime = makeRuntime()
        XCTAssertEqual(runtime.store.state.projects.count, 1)
        XCTAssertEqual(runtime.store.state.projects.first?.rootDirectory, FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
        XCTAssertEqual(runtime.store.allVisibleSessions.count, 1)
        XCTAssertNil(runtime.store.scratchSession, "the hotkey now toggles the main window; no hidden session")
        XCTAssertEqual(runtime.store.state.focusedSessionID, runtime.store.allVisibleSessions.first?.id)
    }

    func testFocusedSessionGetsALayoutAndAControllerLazily() {
        let runtime = makeRuntime()
        let session = runtime.store.focusedSession!
        XCTAssertNil(runtime.existingLayout(for: session.id), "nothing spawned until opened")
        runtime.open(session: session.id)
        let layout = runtime.layout(for: session.id)
        XCTAssertEqual(layout.paneIDs.count, 1)
        let pane = layout.paneIDs[0]
        XCTAssertEqual(runtime.focusedPaneID, pane)
        XCTAssertEqual(runtime.controller(for: pane).state, .running)
        runtime.prepareForQuit()
    }

    func testSplitCloseAndNeighborFocus() {
        let runtime = makeRuntime()
        let session = runtime.store.focusedSession!
        runtime.open(session: session.id)
        let first = runtime.focusedPaneID!
        runtime.splitFocusedPane(axis: .horizontal)
        let second = runtime.focusedPaneID!
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(runtime.layout(for: session.id).paneIDs, [first, second])
        XCTAssertEqual(runtime.controller(for: second).currentDirectory, runtime.controller(for: first).currentDirectory,
                       "split inherits the cwd")
        runtime.focusNeighbor(.left)
        XCTAssertEqual(runtime.focusedPaneID, first)
        runtime.closeFocusedPane()
        XCTAssertEqual(runtime.layout(for: session.id).paneIDs, [second])
        XCTAssertEqual(runtime.focusedPaneID, second)
        runtime.prepareForQuit()
    }

    func testClosingLastPaneClosesSessionAndFocusesAnother() {
        let runtime = makeRuntime()
        let project = runtime.store.state.projects[0]
        let a = runtime.store.focusedSession!
        let b = runtime.newSession(in: project.id)
        XCTAssertEqual(runtime.store.state.focusedSessionID, b.id)
        runtime.closeFocusedPane()
        XCTAssertFalse(runtime.store.state.sessions.contains { $0.id == b.id })
        XCTAssertEqual(runtime.store.state.focusedSessionID, a.id)
        runtime.prepareForQuit()
    }

    func testAgentTitleNamesTheSessionUntilTheUserDoes() {
        let runtime = makeRuntime()
        defer { runtime.prepareForQuit() }
        let session = runtime.store.focusedSession!.id
        runtime.open(session: session)
        let controller = runtime.controller(for: runtime.focusedPaneID!)
        controller.setTerminalTitle(source: controller.view, title: "◐ Claude Code")
        XCTAssertEqual(runtime.store.focusedSession?.name, "Terminal", "the product name is not a session name")
        controller.setTerminalTitle(source: controller.view, title: "◑ Fix the login bug")
        XCTAssertEqual(runtime.store.focusedSession?.name, "Fix the login bug")
        XCTAssertEqual(controller.agentTitle?.state, .busy)
        controller.setTerminalTitle(source: controller.view, title: "✳ Fix the login bug")
        XCTAssertEqual(controller.agentTitle?.state, .idle)
        runtime.store.renameSession(session, to: "Mine")
        controller.setTerminalTitle(source: controller.view, title: "✳ Another topic")
        XCTAssertEqual(runtime.store.focusedSession?.name, "Mine")
        controller.setTerminalTitle(source: controller.view, title: "~/projects")
        XCTAssertNil(controller.agentTitle, "a shell title is not an agent title")
    }

    func testSessionCycling() {
        let runtime = makeRuntime()
        let project = runtime.store.state.projects[0]
        let a = runtime.store.focusedSession!
        let b = runtime.newSession(in: project.id)
        let c = runtime.newSession(in: project.id)
        runtime.focusSession(index: 0)
        XCTAssertEqual(runtime.store.state.focusedSessionID, a.id)
        runtime.focusSession(offset: 1)
        XCTAssertEqual(runtime.store.state.focusedSessionID, b.id)
        runtime.focusSession(offset: -2)
        XCTAssertEqual(runtime.store.state.focusedSessionID, c.id, "wraps around")
        runtime.prepareForQuit()
    }

    func testQuitMovesSessionsToHistoryAndLaunchStartsFresh() async {
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "printf 'REMEMBER-ME\\n'; printf '\\033]7;file://localhost/private/tmp\\007'; sleep 30"],
                        environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
        let session = runtime.store.focusedSession!
        runtime.open(session: session.id)
        let pane = runtime.focusedPaneID!
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, runtime.controller(for: pane).currentDirectory?.path != "/private/tmp" {
            try? await Task.sleep(for: .milliseconds(20))
        }
        runtime.store.renameSession(session.id, to: "Deploy notes")
        runtime.prepareForQuit()
        XCTAssertTrue(StateStore(paths: paths).load().state.sessions.isEmpty, "sessions leave the sidebar on quit")
        XCTAssertTrue(AnteSessionHistoryStore(paths: paths).all().isEmpty,
                      "a plain shell, even renamed and in another folder, is not History: nothing in it can be resumed")

        let relaunched = makeRuntime()
        defer { relaunched.prepareForQuit() }
        XCTAssertEqual(relaunched.store.allVisibleSessions.count, 1, "a launch starts with one fresh session")
        XCTAssertNotEqual(relaunched.store.allVisibleSessions.first?.id, session.id)
        XCTAssertEqual(relaunched.store.state.projects.count, 1, "projects stay")
    }

    func testApplyConfigChangesAppearanceOnLiveControllers() {
        let runtime = makeRuntime()
        let session = runtime.store.focusedSession!
        runtime.open(session: session.id)
        let pane = runtime.focusedPaneID!
        var config = AnteConfig.default
        config.font.size = 19
        config.theme.name = "gruvbox-dark"
        runtime.applyConfig(config)
        XCTAssertEqual(runtime.controller(for: pane).view.font.pointSize, 19)
        XCTAssertEqual(runtime.appearance.theme.name, "Gruvbox Dark")
        runtime.prepareForQuit()
    }
}

extension WorkspaceRuntimeTests {
    func testHistoryKeepsTheProgramNotItsArguments() {
        XCTAssertEqual(WorkspaceRuntime.programName("/usr/bin/curl -H 'Authorization: Bearer abc' https://x"), "curl")
        XCTAssertEqual(WorkspaceRuntime.programName("claude"), "claude")
    }
}
