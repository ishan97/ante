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

    /// macOS hides the environment of Apple's own binaries; agents are never those, so the tests
    /// use an ad-hoc-signed copy of `sleep`, named `sleep`.
    private func ownSleep() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent("sleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["-f", "-s", "-", copy.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return copy
    }

    func testProbeReadsEnvironment() throws {
        let sleep = try ownSleep()
        let process = Process()
        process.executableURL = sleep
        process.arguments = ["5"]
        process.environment = ["CLAUDE_CONFIG_DIR": "/tmp/x y", "OTHER": "1", "PATH": "/usr/bin:/bin"]
        try process.run()
        defer { process.terminate() }
        let env = ForegroundProbe.environment(pid: process.processIdentifier, keys: ["CLAUDE_CONFIG_DIR", "CODEX_HOME"])
        XCTAssertEqual(env, ["CLAUDE_CONFIG_DIR": "/tmp/x y"])
        XCTAssertEqual(ForegroundProbe.commandLine(pid: process.processIdentifier), [sleep.path, "5"], "argv is unchanged")
    }

    func testForegroundInfoCarriesAccountKeys() async throws {
        let sleep = try ownSleep()
        let c = TerminalSessionController(sessionID: SessionID(),
                                          launch: ShellLaunch(executable: "/bin/sh", arguments: ["-c", "CODEX_HOME=/tmp/h ANTE_PANE_ID=p1 OTHER=1 exec '\(sleep.path)' 4"],
                                                              environment: ["PATH=/usr/bin:/bin", "HOME=/tmp"], kind: .other),
                                          workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
        c.start()
        await wait(until: c.foreground?.executableName == "sleep", seconds: 3.5)
        XCTAssertEqual(c.foreground?.environment, ["CODEX_HOME": "/tmp/h", "ANTE_PANE_ID": "p1"])
        c.terminate()
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
