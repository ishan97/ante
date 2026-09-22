// Packages/AnteUI/Tests/AnteUITests/WaitingNotifierTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class WaitingNotifierTests: XCTestCase {
    private func card(_ id: PaneID, _ state: CardState) -> SessionBoardModel.Card {
        SessionBoardModel.Card(id: id, sessionID: SessionID(), sessionName: "api", projectName: "p", agent: .claude,
                               subtitle: "", state: state, since: Date())
    }

    func testFiresOnceWhenAPaneEntersWaitingAndAgainAfterItLeaves() {
        let a = PaneID(), b = PaneID()
        let working = [card(a, .working), card(b, .working)]
        let aWaits = [card(a, .waitingDefinite("needs your permission")), card(b, .working)]
        XCTAssertEqual(WaitingNotifier.newlyWaiting(previous: working, next: aWaits).map(\.id), [a])
        XCTAssertTrue(WaitingNotifier.newlyWaiting(previous: aWaits, next: aWaits).isEmpty, "still waiting: no repeat")
        let probable = [card(a, .waitingProbable), card(b, .working)]
        XCTAssertTrue(WaitingNotifier.newlyWaiting(previous: aWaits, next: probable).isEmpty, "definite → probable is the same column")
        XCTAssertEqual(WaitingNotifier.newlyWaiting(previous: working, next: probable).map(\.id), [a], "the quiet-timeout guess notifies too")
        let back = WaitingNotifier.newlyWaiting(previous: working, next: aWaits)
        XCTAssertEqual(back.count, 1, "left and came back: fires again")
        XCTAssertEqual(WaitingNotifier.newlyWaiting(previous: [], next: aWaits).map(\.id), [a], "a brand-new pane that is already waiting counts")
    }

    func testTheFocusedPaneIsSilentOnlyWhileAnteIsInFront() {
        let a = PaneID()
        let c = card(a, .waitingProbable)
        XCTAssertFalse(WaitingNotifier.shouldNotify(card: c, focusedPane: a, appActive: true))
        XCTAssertTrue(WaitingNotifier.shouldNotify(card: c, focusedPane: a, appActive: false))
        XCTAssertTrue(WaitingNotifier.shouldNotify(card: c, focusedPane: PaneID(), appActive: true))
    }

    func testReasonTextAndSounds() throws {
        XCTAssertEqual(WaitingNotifier.reason(for: .waitingDefinite("needs your permission"), quietSeconds: 8), "needs your permission")
        XCTAssertEqual(WaitingNotifier.reason(for: .waitingProbable, quietSeconds: 8), "Quiet for 8s — probably waiting for you")
        XCTAssertTrue(SystemSounds.names.contains("Glass"))
        let c = try ConfigLoader().parse("[agents]\nnotify = false\nnotify_sound = \"Ping\"")
        XCTAssertFalse(c.agents.notify)
        XCTAssertEqual(c.agents.notifySound, "Ping")
        XCTAssertTrue(AnteConfig.default.agents.notify)
        XCTAssertEqual(AnteConfig.default.agents.notifySound, "Glass")
    }
}

extension WaitingNotifierTests {
    /// End to end through the board: a pane whose foreground process is named `claude` and prints
    /// nothing crosses the quiet threshold, is delivered once, badges the Dock, and is not
    /// delivered again while it keeps waiting.
    func testBoardDeliversOnceWhenARealAgentProcessGoesQuiet() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ante-agent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let root = dir.appendingPathComponent("state")
        let paths = AppPaths(root: root, configRoot: dir.appendingPathComponent("config"))
        var config = AnteConfig.default
        config.agents.quietSeconds = 1
        let runtime = WorkspaceRuntime(paths: paths, config: config, launchFactory: { _ in
            // `exec -a` names the process "claude", which is what the foreground probe classifies on.
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "exec -a claude /bin/sleep 30"], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
        defer { runtime.prepareForQuit() }
        var delivered: [(String, String)] = []
        var badges: [Int] = []
        runtime.board.deliverWaiting = { card, reason in delivered.append((card.sessionName, reason)) }
        runtime.board.setBadge = { badges.append($0) }

        let session = try XCTUnwrap(runtime.store.allVisibleSessions.first)
        runtime.open(session: session.id)
        let pane = try XCTUnwrap(runtime.focusedPaneID)
        _ = runtime.controller(for: pane)   // spawns the stand-in agent

        // Pump the main run loop so the PTY reader, the 2 s foreground probe and its hop back to
        // the main actor all run; the process prints nothing, so the 1 s quiet threshold passes.
        for _ in 0..<60 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            runtime.board.refresh()
            if !delivered.isEmpty { break }
        }
        let c = runtime.controller(for: pane)
        let info = "cards=\(runtime.board.cards.map { "\($0.state) agent=\($0.agent)" }) state=\(c.state) agent=\(c.agent) activity=\(c.activity) fg=\(String(describing: c.foregroundCommand)) lastOut=\(Date().timeIntervalSince(c.lastOutputAt))s layout=\(runtime.existingLayout(for: session.id) != nil) visible=\(runtime.store.allVisibleSessions.count)"
        XCTAssertEqual(delivered.count, 1, "one notification when the pane enters Waiting; \(info)")
        XCTAssertEqual(delivered.first?.1, "Quiet for 1s — probably waiting for you")
        XCTAssertEqual(badges.last, 1)
        runtime.board.refresh(); runtime.board.refresh()
        XCTAssertEqual(delivered.count, 1, "still waiting: no repeat")
    }
}
