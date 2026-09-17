import XCTest
@testable import AnteTerm

final class ShellLaunchBuilderTests: XCTestCase {
    private var integration: InstalledIntegration!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-launch-\(UUID().uuidString)")
        integration = try ShellIntegration.install(into: root, version: "0.1.0")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func env(_ launch: ShellLaunch) -> [String: String] {
        var out: [String: String] = [:]
        for entry in launch.environment {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            out[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return out
    }

    func testShellKindFromPath() {
        XCTAssertEqual(ShellKind(shellPath: "/bin/zsh"), .zsh)
        XCTAssertEqual(ShellKind(shellPath: "/opt/homebrew/bin/bash"), .bash)
        XCTAssertEqual(ShellKind(shellPath: "/opt/homebrew/bin/fish"), .fish)
        XCTAssertEqual(ShellKind(shellPath: "/usr/local/bin/nu"), .other)
    }

    func testZshLaunchPointsZdotdirAtShim() {
        let builder = ShellLaunchBuilder(baseEnvironment: ["HOME": "/Users/t", "PATH": "/usr/bin"],
                                         integration: integration, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/bin/zsh")
        XCTAssertEqual(launch.kind, .zsh)
        XCTAssertEqual(launch.executable, "/bin/zsh")
        XCTAssertEqual(launch.arguments, ["-l"])
        let e = env(launch)
        XCTAssertEqual(e["ZDOTDIR"], integration.zshDirectory.path)
        XCTAssertNil(e["ANTE_USER_ZDOTDIR"])
        XCTAssertEqual(e["ANTE_SHELL_INTEGRATION"], "1")
        XCTAssertEqual(e["TERM"], "xterm-256color")
        XCTAssertEqual(e["COLORTERM"], "truecolor")
        XCTAssertEqual(e["TERM_PROGRAM"], "Ante")
        XCTAssertEqual(e["TERM_PROGRAM_VERSION"], "0.1.0")
        XCTAssertEqual(e["SHELL"], "/bin/zsh")
        XCTAssertEqual(e["LANG"], "en_US.UTF-8")
        XCTAssertEqual(e["HOME"], "/Users/t")
    }

    func testZshLaunchPreservesUsersOwnZdotdir() {
        let builder = ShellLaunchBuilder(baseEnvironment: ["ZDOTDIR": "/Users/t/.config/zsh"],
                                         integration: integration, appVersion: "0.1.0")
        let e = env(builder.makeLaunch(shellPath: "/bin/zsh"))
        XCTAssertEqual(e["ANTE_USER_ZDOTDIR"], "/Users/t/.config/zsh")
        XCTAssertEqual(e["ZDOTDIR"], integration.zshDirectory.path)
    }

    func testBashLaunchUsesInitFile() {
        let builder = ShellLaunchBuilder(baseEnvironment: [:], integration: integration, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/bin/bash")
        XCTAssertEqual(launch.arguments, ["--init-file", integration.bashInitFile.path])
        XCTAssertNil(env(launch)["ZDOTDIR"])
    }

    func testFishLaunchUsesInitCommand() {
        let builder = ShellLaunchBuilder(baseEnvironment: [:], integration: integration, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/opt/homebrew/bin/fish")
        XCTAssertEqual(launch.arguments, ["-l", "-C", "source '\(integration.fishInitFile.path)'"])
    }

    func testUnknownShellGetsPlainLoginAndNoIntegration() {
        let builder = ShellLaunchBuilder(baseEnvironment: [:], integration: integration, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/usr/local/bin/nu")
        XCTAssertEqual(launch.kind, .other)
        XCTAssertEqual(launch.arguments, ["-l"])
        XCTAssertNil(env(launch)["ANTE_SHELL_INTEGRATION"])
    }

    func testIntegrationDisabledLeavesShellAlone() {
        let builder = ShellLaunchBuilder(baseEnvironment: ["ZDOTDIR": "/x"], integration: nil, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/bin/zsh")
        let e = env(launch)
        XCTAssertEqual(e["ZDOTDIR"], "/x")
        XCTAssertNil(e["ANTE_SHELL_INTEGRATION"])
        XCTAssertEqual(e["TERM_PROGRAM"], "Ante")
    }

    func testExtraArgumentsAppend() {
        let builder = ShellLaunchBuilder(baseEnvironment: [:], integration: integration, appVersion: "0.1.0")
        let launch = builder.makeLaunch(shellPath: "/bin/zsh", extraArguments: ["-c", "true"])
        XCTAssertEqual(launch.arguments, ["-l", "-c", "true"])
    }

    func testUserLangIsRespected() {
        let builder = ShellLaunchBuilder(baseEnvironment: ["LANG": "de_DE.UTF-8"], integration: nil, appVersion: "0.1.0")
        XCTAssertEqual(env(builder.makeLaunch(shellPath: "/bin/zsh"))["LANG"], "de_DE.UTF-8")
    }

    func testLoginShellResolvesToAnExecutable() {
        let shell = LoginShell.resolve(environment: ProcessInfo.processInfo.environment)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: shell), shell)
    }

    func testLoginShellFallsBackToZsh() {
        XCTAssertEqual(LoginShell.resolve(environment: [:], passwordEntryShell: nil), "/bin/zsh")
        XCTAssertEqual(LoginShell.resolve(environment: ["SHELL": "/bin/bash"], passwordEntryShell: nil), "/bin/bash")
        XCTAssertEqual(LoginShell.resolve(environment: ["SHELL": "/bin/bash"], passwordEntryShell: "/bin/zsh"), "/bin/zsh")
    }

    func testUsersShellArgumentsReplaceTheLoginDefault() {
        let builder = ShellLaunchBuilder(baseEnvironment: [:], integration: nil, appVersion: "t")
        XCTAssertEqual(builder.makeLaunch(shellPath: "/bin/zsh").arguments, ["-l"])
        XCTAssertEqual(builder.makeLaunch(shellPath: "/bin/zsh", arguments: ["-l", "-c", "tmux new -A"]).arguments, ["-l", "-c", "tmux new -A"])
        XCTAssertEqual(builder.makeLaunch(shellPath: "/bin/zsh", arguments: []).arguments, [], "no login shell if the user says so")
    }
}
