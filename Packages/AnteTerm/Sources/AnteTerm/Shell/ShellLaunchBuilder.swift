import Foundation

public enum ShellKind: String, Equatable, Sendable {
    case zsh, bash, fish, other

    public init(shellPath: String) {
        switch URL(fileURLWithPath: shellPath).lastPathComponent {
        case "zsh": self = .zsh
        case "bash": self = .bash
        case "fish": self = .fish
        default: self = .other
        }
    }
}

/// Everything needed to spawn a shell: the binary, its argv (after argv[0]), and a `KEY=VALUE` environment.
public struct ShellLaunch: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String]
    public let kind: ShellKind

    public init(executable: String, arguments: [String], environment: [String], kind: ShellKind) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.kind = kind
    }
}

/// Builds a `ShellLaunch` from the app's environment, injecting terminal identity and, when
/// integration is enabled, the shim that emits OSC 133/7 — without touching the user's rc files.
public struct ShellLaunchBuilder: Sendable {
    public let baseEnvironment: [String: String]
    public let integration: InstalledIntegration?
    public let appVersion: String

    public init(baseEnvironment: [String: String], integration: InstalledIntegration?, appVersion: String) {
        self.baseEnvironment = baseEnvironment
        self.integration = integration
        self.appVersion = appVersion
    }

    /// `arguments` are the user's `[shell] args` (default `-l`, a login shell); integration adds
    /// what each shell needs on top. `extraArguments` go last (a one-off command, say).
    public func makeLaunch(shellPath: String, arguments userArguments: [String] = ["-l"], extraArguments: [String] = []) -> ShellLaunch {
        let kind = ShellKind(shellPath: shellPath)
        var env = baseEnvironment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Ante"
        env["TERM_PROGRAM_VERSION"] = appVersion
        env["SHELL"] = shellPath
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

        var arguments = userArguments

        if let integration {
            switch kind {
            case .zsh:
                if let userZdotdir = env["ZDOTDIR"], !userZdotdir.isEmpty {
                    env["ANTE_USER_ZDOTDIR"] = userZdotdir
                }
                env["ZDOTDIR"] = integration.zshDirectory.path
                env["ANTE_SHELL_INTEGRATION"] = "1"
            case .bash:
                // `--init-file` replaces the rc file; a login flag would also read the profiles
                // before it, which is what the shim itself takes care of.
                arguments = ["--init-file", integration.bashInitFile.path] + userArguments.filter { $0 != "-l" && $0 != "--login" }
                env["ANTE_SHELL_INTEGRATION"] = "1"
            case .fish:
                arguments = userArguments + ["-C", "source '\(integration.fishInitFile.path)'"]
                env["ANTE_SHELL_INTEGRATION"] = "1"
            case .other:
                break
            }
        }

        arguments += extraArguments
        let flattened = env.keys.sorted().map { "\($0)=\(env[$0]!)" }
        return ShellLaunch(executable: shellPath, arguments: arguments, environment: flattened, kind: kind)
    }
}
