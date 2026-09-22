// Packages/AnteUI/Tests/AnteUITests/SessionBoardTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class SessionBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testBoardRules() {
        let recent = now.addingTimeInterval(-1), old = now.addingTimeInterval(-30)
        XCTAssertEqual(BoardRules.state(agent: .shell, commandRunning: false, lastOutputAt: old, hook: nil, hookAt: nil, now: now, quietSeconds: 8), .idle)
        XCTAssertEqual(BoardRules.state(agent: .shell, commandRunning: true, lastOutputAt: recent, hook: nil, hookAt: nil, now: now, quietSeconds: 8), .working)
        XCTAssertEqual(BoardRules.state(agent: .command, commandRunning: true, lastOutputAt: old, hook: nil, hookAt: nil, now: now, quietSeconds: 8), .working,
                       "a plain command that is quiet is not 'waiting'")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, hook: nil, hookAt: nil, now: now, quietSeconds: 8), .working)
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: old, hook: nil, hookAt: nil, now: now, quietSeconds: 8), .waitingProbable)
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: old, hook: .waiting("permission"), hookAt: now.addingTimeInterval(-5), now: now, quietSeconds: 8),
                       .waitingDefinite("permission"))
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, hook: .waiting("permission"), hookAt: now.addingTimeInterval(-40), now: now, quietSeconds: 8),
                       .waitingDefinite("permission"), "output after a waiting hook is a repaint, not work")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, inputAt: now.addingTimeInterval(-3),
                                        hook: .waiting("permission"), hookAt: now.addingTimeInterval(-40), now: now, quietSeconds: 8),
                       .working, "the user answered after the hook: back to heuristics")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: old, inputAt: now.addingTimeInterval(-20),
                                        hook: .waiting("permission"), hookAt: now.addingTimeInterval(-40), now: now, quietSeconds: 8),
                       .waitingProbable, "answered, then quiet again")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: old, hook: .working, hookAt: now.addingTimeInterval(-2), now: now, quietSeconds: 8), .working)
    }

    func testTheAgentsOwnTitleWins() {
        let recent = now.addingTimeInterval(-1), old = now.addingTimeInterval(-30)
        let busy = AgentTitle(state: .busy, name: "Pong"), idle = AgentTitle(state: .idle, name: "Pong")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: old, title: busy, hook: nil, hookAt: nil, now: now, quietSeconds: 8),
                       .working, "spinning title beats a long quiet")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, title: idle, hook: nil, hookAt: nil, now: now, quietSeconds: 8),
                       .waitingDefinite("waiting for input"), "idle title beats fresh output")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, title: idle,
                                        hook: .waiting("permission"), hookAt: now.addingTimeInterval(-3), now: now, quietSeconds: 8),
                       .waitingDefinite("permission"), "a current hook supplies the reason")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, inputAt: now.addingTimeInterval(-1), title: idle,
                                        hook: .waiting("permission"), hookAt: now.addingTimeInterval(-3), now: now, quietSeconds: 8),
                       .waitingDefinite("waiting for input"), "after the user answered, the hook's reason is stale")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, inputAt: now, title: busy,
                                        hook: .waiting("permission"), hookAt: now.addingTimeInterval(-3), now: now, quietSeconds: 8), .working)
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, title: idle,
                                        notice: "Claude needs your permission", noticeAt: now.addingTimeInterval(-1),
                                        hook: nil, hookAt: nil, now: now, quietSeconds: 8),
                       .waitingDefinite("Claude needs your permission"), "the program's own notification is the reason, no hook needed")
        XCTAssertEqual(BoardRules.state(agent: .claude, commandRunning: true, lastOutputAt: recent, inputAt: now,
                                        notice: "Claude needs your permission", noticeAt: now.addingTimeInterval(-1),
                                        hook: nil, hookAt: nil, now: now, quietSeconds: 8),
                       .working, "answered after the notification: heuristics again")
    }

    private func makeRuntime(script: String) -> (WorkspaceRuntime, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-board-\(UUID().uuidString)")
        let paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
        return (runtime, root)
    }

    /// Resume opens a session in the past session's project and types the command after the prompt.
    func testResumeTypesTheCommandAfterTheFirstPrompt() async {
        let (runtime, root) = makeRuntime(script: "printf '\\033]133;A\\007$ '; cat")
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let past = PastSession(id: "3c2b69dc-f7ea-490e-878b-f85b72bbb5ff", agent: .claude, title: "Fix login", projectPath: "/private/tmp",
                               createdAt: Date(), modifiedAt: Date(), resumeCommand: "claude --resume 3c2b69dc-f7ea-490e-878b-f85b72bbb5ff")
        runtime.isSessionsViewerVisible = true
        runtime.resume(past)
        XCTAssertFalse(runtime.isSessionsViewerVisible)
        let session = runtime.store.focusedSession!
        XCTAssertEqual(session.name, "Fix login")
        XCTAssertEqual(session.workingDirectory.path, "/tmp", "standardized: /private/tmp → /tmp")
        XCTAssertTrue(runtime.store.state.projects.contains { $0.rootDirectory.path == "/tmp" }, "\(runtime.store.state.projects)")
        let controller = runtime.liveController(for: session.id)!
        func screen() -> String { String(decoding: controller.view.getTerminal().getBufferAsData(), as: UTF8.self) }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !screen().contains("claude --resume") {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(screen().contains("claude --resume 3c2b69dc"), screen())
    }

    func testOpeningASessionLeavesTheBoard() {
        let (runtime, root) = makeRuntime(script: "sleep 30")
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let project = runtime.store.state.projects[0]
        let a = runtime.store.focusedSession!
        let b = runtime.newSession(in: project.id)
        runtime.isSessionsViewerVisible = true
        runtime.open(session: a.id)
        XCTAssertFalse(runtime.isSessionsViewerVisible, "sidebar click must dismiss the board")
        XCTAssertEqual(runtime.store.state.focusedSessionID, a.id)
        runtime.isSessionsViewerVisible = true
        runtime.focusSession(offset: 1)
        XCTAssertFalse(runtime.isSessionsViewerVisible, "⌘⇧] must dismiss the board too")
        XCTAssertEqual(runtime.store.state.focusedSessionID, b.id)
    }

    func testClosingAnAgentSessionRecordsHistoryButAPlainShellDoesNot() {
        // `exec -a` names the process "claude", which is what the foreground probe classifies on.
        let (runtime, root) = makeRuntime(script: "exec -a claude /bin/sleep 30")
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let project = runtime.store.state.projects[0]
        let session = runtime.newSession(in: project.id)
        runtime.open(session: session.id)
        runtime.store.renameSession(session.id, to: "deploy")
        let pane = runtime.focusedPaneID!
        // The 2 s foreground probe runs on the main run loop.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, runtime.controller(for: pane).agent != .claude {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(runtime.controller(for: pane).agent, .claude)
        runtime.closeSession(session.id)
        let history = AnteSessionHistoryStore(paths: runtime.paths).all()
        XCTAssertEqual(history.first?.name, "deploy")
        XCTAssertEqual(history.first?.projectPath, project.rootDirectory.path)
        XCTAssertEqual(history.first?.agent, .claude)
        XCTAssertEqual(history.first?.asPastSession.resumeCommand, nil)

        // A plain shell session, even renamed, leaves nothing behind: there is nothing to resume.
        let (shellRuntime, shellRoot) = makeRuntime(script: "sleep 30")
        defer { shellRuntime.prepareForQuit(); try? FileManager.default.removeItem(at: shellRoot) }
        let shell = shellRuntime.newSession(in: shellRuntime.store.state.projects[0].id)
        shellRuntime.open(session: shell.id)
        shellRuntime.store.renameSession(shell.id, to: "notes")
        shellRuntime.closeSession(shell.id)
        XCTAssertTrue(AnteSessionHistoryStore(paths: shellRuntime.paths).all().isEmpty)
    }

    func testBoardCardsReflectLivePanes() async {
        let (runtime, root) = makeRuntime(script: "sleep 30")
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        runtime.open(session: runtime.store.focusedSession!.id)
        try? await Task.sleep(for: .milliseconds(300))
        runtime.board.refresh()
        XCTAssertEqual(runtime.board.cards.count, 1)
        XCTAssertEqual(runtime.board.cards.first?.sessionName, "Terminal")
        runtime.board.ingest([HookEvent(agent: .claude, sessionID: nil, cwd: "/tmp", event: "Notification", meaning: .waiting("needs you"), at: Date())])
        XCTAssertEqual(runtime.board.waitingCount, 0, "hook for a cwd no live pane is in changes nothing")
    }
}
