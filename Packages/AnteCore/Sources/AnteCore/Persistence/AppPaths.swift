import Foundation

/// Where Ante keeps its files. Everything is derived from two injectable roots so tests
/// never touch the real home directory.
public struct AppPaths: Sendable, Equatable {
    /// `~/Library/Application Support/Ante` in production.
    public let root: URL
    /// `~/.config/ante` in production.
    public let configRoot: URL

    /// `~/.ante/accounts` in production: the account folders and their list.
    public let accountsRoot: URL
    /// The home whose `.claude` / `.codex` are the agents' default folders.
    public let home: URL

    /// Without explicit account roots everything stays under `root`, so a test that builds
    /// paths from a scratch directory can never reach the real home's agent folders.
    public init(root: URL, configRoot: URL, accountsRoot: URL? = nil, home: URL? = nil) {
        self.root = root
        self.configRoot = configRoot
        self.accountsRoot = accountsRoot ?? root.appendingPathComponent("accounts", isDirectory: true)
        self.home = home ?? root.appendingPathComponent("home", isDirectory: true)
    }

    public var accountPaths: AccountPaths { AccountPaths(root: accountsRoot, home: home) }

    public static var `default`: AppPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return AppPaths(
            root: appSupport.appendingPathComponent("Ante", isDirectory: true),
            configRoot: home.appendingPathComponent(".config/ante", isDirectory: true),
            accountsRoot: home.appendingPathComponent(".ante/accounts", isDirectory: true),
            home: home
        )
    }

    public var stateFile: URL { root.appendingPathComponent("state.json") }
    /// Legacy (pre quit-to-History); only ever removed now.
    public var scrollbackDirectory: URL { root.appendingPathComponent("scrollback", isDirectory: true) }
    public var shellIntegrationDirectory: URL { root.appendingPathComponent("shell-integration", isDirectory: true) }
    public var configFile: URL { configRoot.appendingPathComponent("config.toml") }
    public var themesDirectory: URL { configRoot.appendingPathComponent("themes", isDirectory: true) }
    public var hooksDirectory: URL { root.appendingPathComponent("hooks", isDirectory: true) }
    /// Claude Code's hook appends its stdin JSON here (one line per event).
    public var claudeHookEventFile: URL { hooksDirectory.appendingPathComponent("claude.jsonl") }
    /// Ante sessions the user closed, for the History list.
    public var historyFile: URL { root.appendingPathComponent("history.json") }
    /// The to-do list and notes behind the toolbar's checklist button.
    public var scratchpadFile: URL { root.appendingPathComponent("scratchpad.json") }
}
