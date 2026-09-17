// Packages/AnteCore/Sources/AnteCore/Agents/AgentKind.swift
import Foundation

/// The CLI agents Ante recognises in a pane's foreground, plus the two non-agent states.
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude, codex, aider, gemini, goose, amp, opencode, cursor, pi
    case shell, command

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .aider: return "Aider"
        case .gemini: return "Gemini CLI"
        case .goose: return "Goose"
        case .amp: return "Amp"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor Agent"
        case .pi: return "Pi"
        case .shell: return "Shell"
        case .command: return "Command"
        }
    }

    public var isAgent: Bool { self != .shell && self != .command }

    /// Executable / script names that identify each agent (matched against the last path component
    /// of the executable and, for interpreters like node/bun/python, the first script argument).
    static let processNames: [AgentKind: Set<String>] = [
        .claude: ["claude", "claude-code"],
        .codex: ["codex", "codex-cli"],
        .aider: ["aider"],
        .gemini: ["gemini"],
        .goose: ["goose"],
        .amp: ["amp"],
        .opencode: ["opencode"],
        .cursor: ["cursor-agent"],
        .pi: ["pi"],
    ]

    static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "-zsh", "-bash", "-fish"]
    static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby"]

    /// Classifies a foreground command line. `argv[0]` may be a full path.
    public static func classify(commandLine: [String]) -> AgentKind {
        guard let first = commandLine.first else { return .shell }
        let exe = (first as NSString).lastPathComponent.lowercased()
        if shells.contains(exe) { return .shell }
        var candidates = [exe]
        if interpreters.contains(exe), commandLine.count > 1 {
            candidates.append((commandLine[1] as NSString).lastPathComponent.lowercased())
            // npm-installed CLIs run as `node …/node_modules/<package>/cli.js`; only the package
            // directory counts, not every folder on the way (a project called "claude" is not Claude).
            let parts = commandLine[1].lowercased().split(separator: "/").map(String.init)
            for (i, part) in parts.enumerated() where (part == "node_modules" || part == ".bin") && i + 1 < parts.count {
                // `@scope/name`: the package is the part after the scope.
                let next = parts[i + 1]
                candidates.append(next.hasPrefix("@") && i + 2 < parts.count ? parts[i + 2] : next)
            }
        }
        for kind in AgentKind.allCases {   // fixed order: no dictionary-iteration surprises
            if let names = processNames[kind], !names.isDisjoint(with: candidates) { return kind }
        }
        return .command
    }

    static let idPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{8,80}$")

    /// The command typed into a fresh shell to continue a past session. Nil when the agent has no
    /// resume flow or the id is not a safe token.
    public func resumeCommand(sessionID: String) -> String? {
        guard Self.idPattern.firstMatch(in: sessionID, range: NSRange(location: 0, length: (sessionID as NSString).length)) != nil else { return nil }
        switch self {
        case .claude: return "claude --resume \(sessionID)"
        case .codex: return "codex resume \(sessionID)"
        case .opencode: return "opencode --session \(sessionID)"
        case .pi: return "pi --session \(sessionID)"
        default: return nil
        }
    }
}
