import XCTest
import AnteCore
@testable import AnteTerm

@MainActor
final class PTYIntegrationTests: XCTestCase {
    private func makeController(script: String, bus: RunEventBus) -> TerminalSessionController {
        let launch = ShellLaunch(
            executable: "/bin/sh",
            arguments: ["-c", script],
            environment: ["PATH=/usr/bin:/bin", "HOME=\(NSHomeDirectory())", "TERM=xterm-256color"],
            kind: .other
        )
        return TerminalSessionController(
            sessionID: SessionID(),
            launch: launch,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            bus: bus
        )
    }

    private func waitForExit(_ controller: TerminalSessionController, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .exited = controller.state { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testProcessExitCodeIsReported() async {
        let controller = makeController(script: "exit 3", bus: RunEventBus())
        controller.start()
        XCTAssertEqual(controller.state, .running)
        await waitForExit(controller)
        XCTAssertEqual(controller.state, .exited(code: 3))
    }

    func testSemanticEventsFlowToBus() async {
        let bus = RunEventBus()
        let stream = bus.events()
        let script = """
        printf '\\033]133;A\\007'; printf '$ '; printf '\\033]133;C\\007'; \
        printf 'hi\\n'; printf '\\033]7;file://localhost/private/tmp\\007'; printf '\\033]133;D;5\\007'
        """
        let controller = makeController(script: script, bus: bus)
        controller.start()

        var events: [SemanticEvent] = []
        let collector = Task {
            for await e in stream {
                events.append(e.event)
                if events.count == 4 { break }
            }
        }
        _ = await collector.result
        XCTAssertEqual(events, [
            .promptStarted,
            .commandStarted,
            .cwdChanged(URL(fileURLWithPath: "/private/tmp")),
            .commandFinished(exitCode: 5),
        ])
        await waitForExit(controller)
        XCTAssertEqual(controller.currentDirectory, URL(fileURLWithPath: "/private/tmp"))
    }

    func testEventsCarryTheControllersSessionID() async {
        let bus = RunEventBus()
        let stream = bus.events()
        let controller = makeController(script: "printf '\\033]133;A\\007'", bus: bus)
        controller.start()
        var first: RunEvent?
        for await e in stream { first = e; break }
        XCTAssertEqual(first?.sessionID, controller.sessionID)
        await waitForExit(controller)
    }

    func testOutputReachesTheTerminalBuffer() async {
        let controller = makeController(script: "printf 'ante-marker-42'; exit 0", bus: RunEventBus())
        controller.start()
        await waitForExit(controller)
        let text = String(decoding: controller.view.getTerminal().getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(text.contains("ante-marker-42"), text)
    }

    func testMissingExecutableFailsCleanly() {
        let launch = ShellLaunch(executable: "/nonexistent/shell", arguments: [], environment: [], kind: .other)
        let controller = TerminalSessionController(sessionID: SessionID(), launch: launch,
                                                   workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
        controller.start()
        guard case let .failed(message) = controller.state else { return XCTFail("expected .failed, got \(controller.state)") }
        XCTAssertTrue(message.contains("/nonexistent/shell"))
    }

    func testRestartAfterExitRunsAgain() async {
        let controller = makeController(script: "exit 1", bus: RunEventBus())
        controller.start()
        await waitForExit(controller)
        XCTAssertEqual(controller.state, .exited(code: 1))
        controller.restart()
        XCTAssertEqual(controller.state, .running)
        await waitForExit(controller)
        XCTAssertEqual(controller.state, .exited(code: 1))
    }

    func testRawWaitStatusIsDecoded() {
        XCTAssertEqual(TerminalSessionController.normalizedExitCode(0), 0)
        XCTAssertEqual(TerminalSessionController.normalizedExitCode(3 << 8), 3)
        XCTAssertEqual(TerminalSessionController.normalizedExitCode(255 << 8), 255)
        XCTAssertNil(TerminalSessionController.normalizedExitCode(9), "killed by SIGKILL")
        XCTAssertNil(TerminalSessionController.normalizedExitCode(nil))
    }

    func testTerminateKillsARunningShell() async {
        let controller = makeController(script: "sleep 30", bus: RunEventBus())
        controller.start()
        try? await Task.sleep(for: .milliseconds(200))
        let pid = controller.view.process.shellPid
        controller.terminate()
        await waitForExit(controller)
        guard case .exited = controller.state else { return XCTFail("still \(controller.state)") }
        // The foreground child must be gone too, not just the shell.
        try? await Task.sleep(for: .milliseconds(100))
        let probe = kill(pid, 0); let reason = errno   // read errno before anything else can clobber it
        XCTAssertEqual(probe, -1, "process group leader still alive")
        XCTAssertEqual(reason, ESRCH)
    }
}
