import XCTest
import AnteCore
@testable import AnteTerm

/// The `claude` / `codex` launcher Ante puts first on PATH: run for real in a pty, in front of a
/// stand-in agent that writes what it was started with to a file.
@MainActor
final class LauncherTests: XCTestCase {
    private var dir: URL!
    private var installed: InstalledIntegration!
    private var accounts: URL!
    private var fakeBin: URL!
    private var out: URL!
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("ante-launch-\(UUID().uuidString)")
        home = dir.appendingPathComponent("home")
        accounts = home.appendingPathComponent(".ante/accounts")
        fakeBin = dir.appendingPathComponent("fakebin")
        out = dir.appendingPathComponent("out")
        try fm.createDirectory(at: accounts, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        installed = try ShellIntegration.install(into: dir.appendingPathComponent("integration"), version: "t")
        for agent in ["claude", "codex"] {
            let fake = fakeBin.appendingPathComponent(agent)
            let var_ = agent == "claude" ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
            try Data("#!/bin/sh\nprintf 'CFG=%s ARGS=%s\\n' \"${\(var_)-<unset>}\" \"$*\" > '\(out.path)'\n".utf8).write(to: fake)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        }
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func folder(_ id: String, agent: String = "claude") -> String { accounts.appendingPathComponent("\(agent)/\(id)").path }

    /// Two Claude accounts: the default-folder login and a folder account.
    private func writeTwoAccounts(extra: String = "") throws {
        try fm.createDirectory(atPath: folder("k3x9q2m7"), withIntermediateDirectories: true)
        let tsv = """
        # agent\tid\tfolder\tname\temail\torg\tplan
        claude\tdefault\t\tPersonal\tme@home.com\t\tMax
        claude\tk3x9q2m7\t\(folder("k3x9q2m7"))\tWork\tme@work.com\tWork Inc\tPro
        \(extra)
        """
        try Data(tsv.utf8).write(to: accounts.appendingPathComponent("accounts.tsv"))
    }

    private func environment(_ extra: [String: String] = [:]) -> [String] {
        var env = ["PATH": "\(installed.binDirectory.path):\(fakeBin.path):/usr/bin:/bin", "HOME": home.path,
                   "TERM": "xterm-256color", "ANTE_ACCOUNTS_DIR": accounts.path]
        env.merge(extra) { $1 }
        return env.map { "\($0)=\($1)" }
    }

    /// Runs `script` under `/bin/sh` in a pty (a controlling terminal, as in a pane).
    private func run(_ script: String, env: [String: String] = [:]) -> TerminalSessionController {
        let launch = ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: environment(env), kind: .other)
        let controller = TerminalSessionController(sessionID: SessionID(), launch: launch, workingDirectory: dir, bus: RunEventBus())
        controller.start()
        return controller
    }

    private func screen(_ c: TerminalSessionController) -> String { String(decoding: c.view.getTerminal().getBufferAsData(), as: UTF8.self) }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func waitForExit(_ c: TerminalSessionController) async -> Int32? {
        await waitUntil { if case .exited = c.state { return true }; return false }
        if case let .exited(code) = c.state { return code }
        return nil
    }

    private func result() -> String? {
        (try? String(contentsOf: out, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Passing straight through

    func testNonTTYPassesThrough() async throws {
        try writeTwoAccounts()
        let c = run("echo | claude -p hi > /dev/null")
        _ = await waitForExit(c)
        XCTAssertEqual(result(), "CFG=<unset> ARGS=-p hi")
        XCTAssertFalse(screen(c).contains("Which"))
    }

    func testSingleAccountNoPicker() async throws {
        try Data("claude\tdefault\t\tPersonal\t\t\t\n".utf8).write(to: accounts.appendingPathComponent("accounts.tsv"))
        _ = await waitForExit(run("claude go"))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=go")
    }

    func testSingleFolderAccountIsUsed() async throws {
        try fm.createDirectory(atPath: folder("k3x9q2m7"), withIntermediateDirectories: true)
        try Data("claude\tk3x9q2m7\t\(folder("k3x9q2m7"))\tWork\t\t\t\n".utf8).write(to: accounts.appendingPathComponent("accounts.tsv"))
        _ = await waitForExit(run("claude go"))
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=go", "the only account, not the signed-out default folder")
    }

    /// Two Antes' launcher directories on PATH (an Ante started from another Ante's pane).
    func testTwoLauncherDirectoriesDoNotLoop() async throws {
        try writeTwoAccounts()
        let other = try ShellIntegration.install(into: dir.appendingPathComponent("integration2"), version: "u")
        let c = run("claude --version", env: ["PATH": "\(installed.binDirectory.path):\(other.binDirectory.path):\(fakeBin.path):/usr/bin:/bin"])
        let code = await waitForExit(c)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(result(), "CFG=<unset> ARGS=--version")
    }

    /// The folder column is never trusted: a hostile one, a bad id or a missing folder is skipped.
    func testFolderComesFromValidatedIDOnly() async throws {
        try writeTwoAccounts(extra: "claude\tzz9\t/tmp/evil dir; touch x\tEvil\t\t\t\nclaude\t../up\t/x\tUp\t\t\t\nclaude\tgone1234\t/y\tGone\t\t\t")
        try Data("zz9\n".utf8).write(to: accounts.appendingPathComponent("default-claude"))
        try fm.createDirectory(atPath: folder("zz9"), withIntermediateDirectories: true)
        _ = await waitForExit(run("claude"))
        XCTAssertEqual(result(), "CFG=\(folder("zz9")) ARGS=", "the folder Ante would use, not the one written in the file")
    }

    func testPickerPrintsNamesLiterally() async throws {
        try writeTwoAccounts(extra: "")
        let tsv = try String(contentsOf: accounts.appendingPathComponent("accounts.tsv"), encoding: .utf8)
            .replacingOccurrences(of: "\tWork\t", with: "\tWo\\e]0;PWNED\\arkX\t")
        try Data(tsv.utf8).write(to: accounts.appendingPathComponent("accounts.tsv"))
        let c = run("claude")
        await waitUntil { self.screen(c).contains("Which") }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(screen(c).contains("Wo\\e]0;PWNED\\arkX"), screen(c))
        c.view.send(txt: "\u{1b}")
        _ = await waitForExit(c)
    }

    func testMissingAccountsFilePassesThrough() async throws {
        _ = await waitForExit(run("claude go"))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=go")
    }

    func testDefaultUsed() async throws {
        try writeTwoAccounts()
        try Data("k3x9q2m7\n".utf8).write(to: accounts.appendingPathComponent("default-claude"))
        _ = await waitForExit(run("claude"))
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=")
    }

    func testExplicitVariablePassesThrough() async throws {
        try writeTwoAccounts()
        _ = await waitForExit(run("claude x", env: ["CLAUDE_CONFIG_DIR": "/x"]))
        XCTAssertEqual(result(), "CFG=/x ARGS=x")
    }

    func testAnteAccountDefaultUnsets() async throws {
        try writeTwoAccounts()
        _ = await waitForExit(run("ANTE_ACCOUNT=default claude --resume abcdefgh", env: ["CLAUDE_CONFIG_DIR": "/x"]))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=--resume abcdefgh")
    }

    func testApiKeyPassesThrough() async throws {
        try writeTwoAccounts()
        let c = run("claude", env: ["ANTHROPIC_API_KEY": "k"])
        _ = await waitForExit(c)
        XCTAssertEqual(result(), "CFG=<unset> ARGS=")
        XCTAssertFalse(screen(c).contains("Which"))
    }

    func testInfoFlagsPassThrough() async throws {
        try writeTwoAccounts()
        _ = await waitForExit(run("claude --version"))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=--version")
        _ = await waitForExit(run("claude auth status"))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=auth status")
    }

    func testMissingRealBinaryIsCommandNotFound() async throws {
        try writeTwoAccounts()
        try fm.removeItem(at: fakeBin.appendingPathComponent("claude"))
        let c = run("claude")
        let code = await waitForExit(c)
        XCTAssertEqual(code, 127)
        XCTAssertTrue(screen(c).contains("command not found: claude"), screen(c))
    }

    // MARK: - The picker

    func testPickerShowsAccounts() async throws {
        try writeTwoAccounts()
        let c = run("claude")
        await waitUntil { screen(c).contains("Which Claude account?") }
        let text = screen(c)
        XCTAssertTrue(text.contains("Personal") && text.contains("me@home.com") && text.contains("Work") && text.contains("Pro"), text)
        c.terminate()
    }

    func testPickerArrowEnterChoosesSecond() async throws {
        try writeTwoAccounts()
        let c = run("claude --resume abcdefgh")
        await waitUntil { screen(c).contains("Which Claude account?") }
        c.view.send(txt: "\u{1b}[B")
        try await Task.sleep(for: .milliseconds(150))
        c.view.send(txt: "\r")
        _ = await waitForExit(c)
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=--resume abcdefgh")
    }

    func testPickerEnterOnFirstIsDefaultFolderAccount() async throws {
        try writeTwoAccounts()
        let c = run("claude")
        await waitUntil { screen(c).contains("Which Claude account?") }
        c.view.send(txt: "\r")
        _ = await waitForExit(c)
        XCTAssertEqual(result(), "CFG=<unset> ARGS=")
    }

    func testPickerEscCancels() async throws {
        try writeTwoAccounts()
        let c = run("claude; echo status=$?")
        await waitUntil { screen(c).contains("Which Claude account?") }
        c.view.send(txt: "\u{1b}")
        _ = await waitForExit(c)
        XCTAssertNil(result(), "the agent never ran")
        XCTAssertTrue(screen(c).contains("status=130"), screen(c))
    }

    func testPickerDMakesDefault() async throws {
        try writeTwoAccounts()
        let c = run("claude")
        await waitUntil { screen(c).contains("Which Claude account?") }
        c.view.send(txt: "\u{1b}[B")
        try await Task.sleep(for: .milliseconds(150))
        c.view.send(txt: "d")
        _ = await waitForExit(c)
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=")
        XCTAssertEqual(try String(contentsOf: accounts.appendingPathComponent("default-claude"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), "k3x9q2m7")
    }

    func testCodexUsesItsOwnAccounts() async throws {
        try writeTwoAccounts(extra: "codex\taaaa1111\t\(folder("aaaa1111", agent: "codex"))\tSpare\t\t\t")
        _ = await waitForExit(run("codex"))
        XCTAssertEqual(result(), "CFG=<unset> ARGS=", "one Codex account: no picker, and its folder isn't the default one")
    }

    // MARK: - Links

    func testLauncherWarnsOnBrokenLinkButStarts() async throws {
        try writeTwoAccounts()
        try fm.createDirectory(atPath: folder("k3x9q2m7") + "/projects", withIntermediateDirectories: true)
        try Data("k3x9q2m7\n".utf8).write(to: accounts.appendingPathComponent("default-claude"))
        let c = run("claude", env: ["ANTE_SHARED_CLAUDE": "projects skills state_*.sqlite"])
        _ = await waitForExit(c)
        XCTAssertTrue(screen(c).contains("ante: projects"), screen(c))
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=")
    }

    func testLauncherCreatesMissingLinkWhenTargetExists() async throws {
        try writeTwoAccounts()
        try fm.createDirectory(at: home.appendingPathComponent(".claude/skills"), withIntermediateDirectories: true)
        try Data("k3x9q2m7\n".utf8).write(to: accounts.appendingPathComponent("default-claude"))
        _ = await waitForExit(run("claude", env: ["ANTE_SHARED_CLAUDE": "skills plans"]))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: folder("k3x9q2m7") + "/skills"), home.appendingPathComponent(".claude/skills").path)
        XCTAssertFalse(fm.fileExists(atPath: folder("k3x9q2m7") + "/plans"), "no link to a target that doesn't exist")
    }

    func testLauncherLinksDatabasesMatchingAGlob() async throws {
        try fm.createDirectory(atPath: folder("k3x9q2m7", agent: "codex"), withIntermediateDirectories: true)
        try Data("codex\tdefault\t\tPersonal\t\t\t\ncodex\tk3x9q2m7\tx\tWork\t\t\t\n".utf8)
            .write(to: accounts.appendingPathComponent("accounts.tsv"))
        try Data("k3x9q2m7\n".utf8).write(to: accounts.appendingPathComponent("default-codex"))
        let codexHome = home.appendingPathComponent(".codex")
        try fm.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data().write(to: codexHome.appendingPathComponent("state_7.sqlite"))
        _ = await waitForExit(run("codex", env: ["ANTE_SHARED_CODEX": "state_*.sqlite"]))
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7", agent: "codex")) ARGS=")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: folder("k3x9q2m7", agent: "codex") + "/state_7.sqlite"),
                       codexHome.appendingPathComponent("state_7.sqlite").path)
    }

    // MARK: - Install and PATH

    func testLaunchersAreInstalledExecutable() throws {
        for name in ["claude", "codex"] {
            let path = installed.binDirectory.appendingPathComponent(name).path
            let mode = try fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int
            XCTAssertEqual(mode, 0o755, name)
        }
    }

    private func interactiveZsh(zshrc: String) throws -> (TerminalSessionController, () -> String) {
        try Data(zshrc.utf8).write(to: home.appendingPathComponent(".zshrc"))
        var base = ["PATH": "\(fakeBin.path):/usr/bin:/bin", "HOME": home.path, "TERM": "xterm-256color", "ZDOTDIR": home.path]
        base["ANTE_ACCOUNTS_DIR"] = accounts.path
        let launch = ShellLaunchBuilder(baseEnvironment: base, integration: installed, appVersion: "t")
            .makeLaunch(shellPath: "/bin/zsh", arguments: ["-l"], extraEnvironment: ["ANTE_ACCOUNTS_DIR": accounts.path])
        let c = TerminalSessionController(sessionID: SessionID(), launch: launch, workingDirectory: dir, bus: RunEventBus())
        c.start()
        return (c, { self.screen(c) })
    }

    func testAliasFlagsReachRealBinary() async throws {
        try writeTwoAccounts()
        try Data("k3x9q2m7\n".utf8).write(to: accounts.appendingPathComponent("default-claude"))
        let (c, _) = try interactiveZsh(zshrc: "alias claude='claude --flag'\nPS1='$ '\n")
        try await Task.sleep(for: .milliseconds(700))
        c.view.send(txt: "claude go\r")
        await waitUntil { self.result() != nil }
        XCTAssertEqual(result(), "CFG=\(folder("k3x9q2m7")) ARGS=--flag go")
        c.terminate()
    }

    func testPathIsReassertedAtPrompt() async throws {
        let (c, _) = try interactiveZsh(zshrc: "PS1='$ '\n")
        try await Task.sleep(for: .milliseconds(700))
        c.view.send(txt: "PATH=/usr/bin:/bin\r")
        try await Task.sleep(for: .milliseconds(200))
        c.view.send(txt: "print -r -- $PATH > '\(out.path)'\r")
        await waitUntil { self.result() != nil }
        XCTAssertTrue(result()?.hasPrefix(installed.binDirectory.path + ":") == true, result() ?? "nil")
        c.terminate()
    }
}
