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

    // MARK: - ⌘⌫

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testEraseInputClearsTheShellLineWhereverTheCursorIs() async {
        let launch = ShellLaunch(executable: "/bin/zsh", arguments: ["-f"],
                                 environment: ["PATH=/usr/bin:/bin", "HOME=\(NSHomeDirectory())", "TERM=xterm-256color", "PS1=$ "],
                                 kind: .other)
        let controller = TerminalSessionController(sessionID: SessionID(), launch: launch,
                                                   workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
        controller.start()
        try? await Task.sleep(for: .milliseconds(500))
        controller.view.send(txt: "echo hello world")
        controller.view.send(txt: "\u{1b}[D\u{1b}[D\u{1b}[D\u{1b}[D\u{1b}[D")   // cursor into "world"
        try? await Task.sleep(for: .milliseconds(150))
        controller.eraseInput()
        try? await Task.sleep(for: .milliseconds(150))
        controller.view.send(txt: "echo ERASED-$((40+2))\n")
        // Had anything of "echo hello world" survived, the shell would print something else.
        func lines() -> [String] {
            String(decoding: controller.view.getTerminal().getBufferAsData(), as: UTF8.self)
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        await waitUntil { lines().contains("ERASED-42") }
        XCTAssertTrue(lines().contains("ERASED-42"), lines().joined(separator: " / "))
        XCTAssertFalse(lines().contains { $0.contains("hello") || $0.contains("world") }, lines().joined(separator: " / "))
        controller.terminate()
        await waitForExit(controller)
    }

    /// A stand-in `claude` that records the bytes it receives, raw, up to `count`: `dd` via a
    /// symlink of that name, so the foreground probe sees a process called claude (a shell script
    /// would be `sh`). Returns the running controller and the file the bytes land in.
    private func startFakeClaude(count: Int) async throws -> (TerminalSessionController, received: URL, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ante-erase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let received = dir.appendingPathComponent("received")
        let fake = dir.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(atPath: fake.path, withDestinationPath: "/bin/dd")
        let controller = makeController(
            script: "stty raw -echo; printf ready; exec '\(fake.path)' bs=1 count=\(count) of='\(received.path)' 2>/dev/null",
            bus: RunEventBus())
        controller.start()
        await waitUntil { String(decoding: controller.view.getTerminal().getBufferAsData(), as: UTF8.self).contains("ready") }
        try? await Task.sleep(for: .milliseconds(100))   // past the exec
        return (controller, received, { try? FileManager.default.removeItem(at: dir) })
    }

    private let claudeChunks = InputEraser.chunks(for: .claude, commandLine: ["claude"])

    func testEraseInputTypesClaudesRoundsAtAProgramNamedClaude() async throws {
        let expected = claudeChunks.flatMap { $0 }
        let (controller, received, cleanup) = try await startFakeClaude(count: expected.count)
        defer { cleanup() }
        controller.eraseInput()
        XCTAssertEqual(controller.agent, .claude)
        await waitForExit(controller)
        XCTAssertEqual(Array(try Data(contentsOf: received)), expected)
    }

    func testASecondEraseRestartsTheSequence() async throws {
        // The first press's later chunks are dropped; the second press sends the whole sequence.
        let expected = claudeChunks[0] + claudeChunks.flatMap { $0 }
        let (controller, received, cleanup) = try await startFakeClaude(count: expected.count)
        defer { cleanup() }
        controller.eraseInput()
        controller.eraseInput()
        await waitForExit(controller)
        XCTAssertEqual(Array(try Data(contentsOf: received)), expected)
    }

    func testTypingStopsAnEraseStillInProgress() async throws {
        // Keys typed right after ⌘⌫ must not be erased by the rest of its rounds.
        let (controller, received, cleanup) = try await startFakeClaude(count: 4096)
        defer { cleanup() }
        controller.eraseInput()
        controller.view.onUserInput?()   // what the key monitor and paste report before the key goes out
        controller.view.send(txt: "x")
        try? await Task.sleep(for: .milliseconds(Int(InputEraser.chunkInterval * 1000) * claudeChunks.count + 300))
        controller.terminate()
        await waitForExit(controller)
        XCTAssertEqual(Array(try Data(contentsOf: received)), claudeChunks[0] + Array("x".utf8))
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
