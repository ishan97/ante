// Packages/AnteTerm/Tests/AnteTermTests/ForegroundProbeTests.swift
import XCTest
import AnteCore
@testable import AnteTerm

@MainActor
final class ForegroundProbeTests: XCTestCase {
    func testCommandLineOfSelf() {
        let argv = ForegroundProbe.commandLine(pid: getpid())
        XCTAssertFalse(argv.isEmpty)
        XCTAssertTrue(argv[0].lowercased().contains("xctest") || argv[0].lowercased().contains("swift"), "\(argv)")
    }

    private func controller(_ exe: String, _ args: [String]) -> TerminalSessionController {
        TerminalSessionController(sessionID: SessionID(),
                                  launch: ShellLaunch(executable: exe, arguments: args, environment: ["PATH=/usr/bin:/bin", "HOME=/tmp"], kind: .other),
                                  workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
    }

    private func wait(until condition: @autoclosure () -> Bool, seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !condition() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testForegroundCommandIsDetected() async {
        let c = controller("/bin/sh", ["-c", "sleep 4"])
        c.start()
        await wait(until: c.foreground?.executableName == "sleep", seconds: 3.5)
        XCTAssertEqual(c.foreground?.executableName, "sleep", "\(String(describing: c.foreground))")
        XCTAssertEqual(c.agent, .command)
        XCTAssertEqual(c.foregroundCommand, "sleep 4")
        c.terminate()
    }

    func testInteractiveShellIsClassifiedAsShell() async {
        let c = controller("/bin/zsh", ["-f", "-i"])
        c.start()
        await wait(until: c.foreground != nil, seconds: 3.5)
        XCTAssertEqual(c.agent, .shell, "\(String(describing: c.foreground))")
        c.terminate()
    }

    func testLastOutputAtAdvancesWithOutput() async {
        let c = controller("/bin/sh", ["-c", "sleep 0.5; echo later; sleep 2"])
        let started = Date()
        c.start()
        await wait(until: c.lastOutputAt.timeIntervalSince(started) > 0.4, seconds: 3)
        XCTAssertGreaterThan(c.lastOutputAt.timeIntervalSince(started), 0.4)
        c.terminate()
    }
}
