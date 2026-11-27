// Packages/AnteCore/Sources/AnteCore/Accounts/AccountFolder.swift
import Foundation

/// One entry of an agent's folder that every account shares through a link.
public enum SharedEntry: Equatable, Sendable {
    /// A folder; created empty in the default folder when missing, so the link never dangles.
    case folder(String)
    /// A file. `seed` is what a missing file is created with; nil links it only once it exists.
    case file(String, seed: String?)
    /// SQLite databases matching a glob (`state_*.sqlite`): linked only when they exist, never created.
    case database(glob: String)

    var name: String {
        switch self {
        case let .folder(name), let .file(name, _): return name
        case let .database(glob): return glob
        }
    }
}

public struct AccountFolderProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A real file or folder sits where the shared link belongs: the agent wrote its own copy.
        case realItemWhereLinkBelongs
        /// A link exists but points somewhere other than the shared entry.
        case linkPointsElsewhere
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

/// Builds and checks an account's folder: links back into the agent's default folder for
/// everything except identity, org policy, live-process state and caches, so every account sees
/// the same conversations and setup and only the sign-in differs.
///
/// Ante never changes the content of the default folder. It only creates *missing, empty*
/// shared entries there so links never dangle, and it never overwrites or merges a real item it
/// finds where a link belongs (that is reported by `verify`).
public enum AccountFolder {
    public static func shared(for agent: AccountAgent) -> [SharedEntry] {
        switch agent {
        case .claude:
            return ["projects", "paste-cache", "file-history", "todos", "plans", "session-env", "shell-snapshots",
                    "skills", "commands", "agents", "plugins", "output-styles", "mods"].map(SharedEntry.folder)
                + [.file("history.jsonl", seed: ""), .file("CLAUDE.md", seed: ""), .file("settings.json", seed: "{}\n"),
                   .file("keybindings.json", seed: nil)]
        case .codex:
            return ["sessions", "archived_sessions", "prompts", "skills", "rules", "memories", "sqlite",
                    "thread-writer-locks"].map(SharedEntry.folder)
                + [.file("config.toml", seed: ""), .file("AGENTS.md", seed: nil), .file("history.jsonl", seed: ""),
                   .file("session_index.jsonl", seed: "")]
                + ["state_*.sqlite", "thread_history_*.sqlite", "goals_*.sqlite", "memories_*.sqlite"].map { SharedEntry.database(glob: $0) }
        }
    }

    /// The shared names (database entries as their glob), for the launcher's own link check.
    public static func sharedNames(for agent: AccountAgent) -> [String] { shared(for: agent).map(\.name) }

    /// Creates the account folder and any missing links. Safe to run before every start.
    public static func prepare(_ account: AgentAccount, paths: AccountPaths) throws {
        guard !account.isDefaultFolder else { return }
        let fm = FileManager.default
        let source = account.agent.defaultFolder(home: paths.home)
        let folder = account.folder(in: paths)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, target) in targets(for: account.agent, source: source) {
            let link = folder.appendingPathComponent(name)
            if exists(link) { continue }   // a link already, or a real item we must not touch
            if !exists(target) {
                guard let entry = shared(for: account.agent).first(where: { $0.name == name }) else { continue }
                switch entry {
                case .folder:
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                case let .file(_, seed?):
                    try Data(seed.utf8).write(to: target, options: .withoutOverwriting)
                case .file(_, nil), .database:
                    continue
                }
            }
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        }
    }

    /// What is wrong with an account's links, without changing anything.
    public static func verify(_ account: AgentAccount, paths: AccountPaths) -> [AccountFolderProblem] {
        guard !account.isDefaultFolder else { return [] }
        let folder = account.folder(in: paths)
        let source = account.agent.defaultFolder(home: paths.home)
        var problems: [AccountFolderProblem] = []
        for (name, target) in targets(for: account.agent, source: source) {
            let link = folder.appendingPathComponent(name)
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
                if URL(fileURLWithPath: destination).standardizedFileURL.path != target.standardizedFileURL.path {
                    problems.append(AccountFolderProblem(name: name, kind: .linkPointsElsewhere))
                }
            } else if exists(link) {
                problems.append(AccountFolderProblem(name: name, kind: .realItemWhereLinkBelongs))
            }
        }
        return problems
    }

    /// Seeds a new account's `.claude.json` so it doesn't replay first-run screens and keeps
    /// the person's MCP servers and per-project trust. Never copies identity.
    public static func seedClaudeConfig(from source: URL, to destination: URL) throws {
        guard let data = try? Data(contentsOf: source),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        var seeded: [String: Any] = [:]
        for key in ["mcpServers", "hasCompletedOnboarding", "lastOnboardingVersion", "theme"] {
            if let value = root[key] { seeded[key] = value }
        }
        if let projects = root["projects"] as? [String: Any] {
            seeded["projects"] = projects.compactMapValues { value -> [String: Any]? in
                guard let project = value as? [String: Any] else { return nil }
                return project.filter { !$0.key.hasPrefix("last") }
            }
        }
        let out = try JSONSerialization.data(withJSONObject: seeded, options: [.prettyPrinted, .sortedKeys])
        try AtomicFile.write(out, to: destination)
    }

    /// Deletes an account folder: links are unlinked first, never followed.
    public static func discard(_ folder: URL) throws {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let item = folder.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: item.path)) != nil {
                guard unlink(item.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            }
        }
        if exists(folder) { try fm.removeItem(at: folder) }
    }

    // MARK: - Helpers

    /// Each shared name with its target in the default folder; database globs expand to the
    /// databases that exist there now.
    private static func targets(for agent: AccountAgent, source: URL) -> [(name: String, target: URL)] {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        return shared(for: agent).flatMap { entry -> [(name: String, target: URL)] in
            switch entry {
            case let .folder(name), let .file(name, _):
                return [(name, source.appendingPathComponent(name))]
            case let .database(glob):
                return existing.filter { fnmatch(glob, $0, 0) == 0 }.sorted().map { ($0, source.appendingPathComponent($0)) }
            }
        }
    }

    /// True for anything at the path, a dangling link included.
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
}
