// Packages/AnteCore/Sources/AnteCore/Accounts/AgentAccount.swift
import Foundation

/// The agents whose sign-ins Ante can keep apart. Each keeps a whole sign-in in one folder,
/// chosen by an environment variable; unset means the agent's own default folder.
public enum AccountAgent: String, Codable, Sendable, CaseIterable, Hashable {
    case claude, codex

    public init?(agentKind: AgentKind) {
        switch agentKind {
        case .claude: self = .claude
        case .codex: self = .codex
        default: return nil
        }
    }

    public var agentKind: AgentKind {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    public var displayName: String { agentKind.displayName }

    /// The command the person types.
    public var executable: String { rawValue }

    /// The variable that points the agent at another folder.
    public var configVariable: String {
        switch self {
        case .claude: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        }
    }

    /// Where the agent keeps its sign-in when the variable is unset.
    public func defaultFolder(home: URL) -> URL {
        switch self {
        case .claude: return home.appendingPathComponent(".claude")
        case .codex: return home.appendingPathComponent(".codex")
        }
    }
}

/// One sign-in. The account that lives in the agent's default folder (the login the person had
/// before Ante knew about accounts) runs with the variable *unset*: setting it, even to the
/// default folder, would make Claude Code look for a different keychain item.
public struct AgentAccount: Hashable, Codable, Sendable, Identifiable {
    /// The id of the default-folder account; every other id is 8 lowercase alphanumerics.
    public static let defaultFolderID = "default"

    public let id: String
    public let agent: AccountAgent
    public var name: String
    public var email: String?
    public var org: String?
    public var plan: String?
    public let isDefaultFolder: Bool

    public init(id: String, agent: AccountAgent, name: String, email: String?, org: String?, plan: String?, isDefaultFolder: Bool) {
        self.id = id
        self.agent = agent
        self.name = name
        self.email = email
        self.org = org
        self.plan = plan
        self.isDefaultFolder = isDefaultFolder
    }

    public func folder(in paths: AccountPaths) -> URL {
        isDefaultFolder ? agent.defaultFolder(home: paths.home) : paths.folder(agent: agent, id: id)
    }
}

/// Where accounts live. Both roots are injectable so tests never touch the real home.
public struct AccountPaths: Sendable, Equatable {
    /// `~/.ante/accounts` in production.
    public let root: URL
    /// The home whose `.claude` / `.codex` are the default folders.
    public let home: URL

    public init(root: URL, home: URL) {
        self.root = root
        self.home = home
    }

    public var accountsFile: URL { root.appendingPathComponent("accounts.tsv") }

    public func defaultFile(for agent: AccountAgent) -> URL { root.appendingPathComponent("default-\(agent.rawValue)") }

    public func folder(agent: AccountAgent, id: String) -> URL {
        root.appendingPathComponent(agent.rawValue).appendingPathComponent(id)
    }
}
