// Packages/AnteUI/Sources/AnteUI/Accounts/AccountsModel.swift
import Foundation
import Observation
import AnteCore

/// An account whose folder is ready and whose login command is about to run.
public struct PendingAccount: Equatable, Sendable {
    public let account: AgentAccount
    /// Typed into a pane: signs in to this account's folder.
    public let loginCommand: String
}

public enum AddOutcome: Equatable, Sendable {
    case added(AgentAccount)
    /// The sign-in was the same as an account already listed; it was signed out and discarded.
    case duplicate(of: AgentAccount)
    case failed
}

/// The signed-in Claude and Codex accounts, each agent's default, and what is wrong with them.
/// The list and defaults live in `AccountStore` files that the launcher reads (and writes, for
/// "make default"); the model watches that folder and reloads when they change.
@MainActor
@Observable
public final class AccountsModel {
    public let paths: AccountPaths
    private let cli: AgentCLIRunning
    private let store: AccountStore
    private let limitsSource: UsageLimitsFetching
    /// What is left of each account's limits, keyed like `signedIn`. A failed check keeps the
    /// last numbers rather than blanking the line.
    private var usageLimits: [String: UsageLimits] = [:]
    /// Antigravity's limits (its one sign-in); nil until checked or when agy never signed in.
    public private(set) var antigravityLimits: UsageLimits?
    public private(set) var accounts: [AgentAccount] = []
    private var defaults: [AccountAgent: String] = [:]
    /// Signed in or not as of the last status check, keyed by `"<agent>/<id>"` (both agents'
    /// default logins have the id `default`).
    private var signedIn: [String: Bool] = [:]

    /// The Google account Antigravity CLI last signed in as. Antigravity keeps one sign-in in the
    /// Keychain, shared with the Antigravity app, so it is shown but never chosen.
    public private(set) var antigravitySignIn: AntigravitySignIn?

    /// Whether the account was signed in when last checked; nil before the first check.
    public func isSignedIn(_ account: AgentAccount) -> Bool? { signedIn[Self.key(account)] }

    private static func key(_ account: AgentAccount) -> String { "\(account.agent.rawValue)/\(account.id)" }

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    public init(paths: AccountPaths, cli: AgentCLIRunning, limits: UsageLimitsFetching? = nil) {
        self.paths = paths
        self.cli = cli
        self.limitsSource = limits ?? UsageLimitsClient(home: paths.home)
        self.store = AccountStore(paths: paths)
        reload()
    }

    // MARK: - Reading

    public func reload() {
        accounts = store.load()
        defaults = Dictionary(uniqueKeysWithValues: AccountAgent.allCases.compactMap { agent in
            store.defaultAccountID(for: agent).map { (agent, $0) }
        })
    }

    public func accounts(for agent: AccountAgent) -> [AgentAccount] { accounts.filter { $0.agent == agent } }

    public func account(id: String?, agent: AccountAgent) -> AgentAccount? {
        guard let id else { return nil }
        return accounts.first { $0.agent == agent && $0.id == id }
    }

    public func defaultAccount(for agent: AccountAgent) -> AgentAccount? { account(id: defaults[agent], agent: agent) }

    /// Ante asks only when there is a real choice and no default made it already.
    public func needsAsking(_ agent: AccountAgent) -> Bool {
        accounts(for: agent).count >= 2 && defaultAccount(for: agent) == nil
    }

    /// The account to start without asking: the default, or the only one. Nil when Ante must ask
    /// or when there are no accounts (then the agent starts as it always did).
    public func automaticAccount(for agent: AccountAgent) -> AgentAccount? {
        if let chosen = defaultAccount(for: agent) { return chosen }
        let list = accounts(for: agent)
        return list.count == 1 ? list[0] : nil
    }

    public func problems(for account: AgentAccount) -> [AccountFolderProblem] { AccountFolder.verify(account, paths: paths) }

    // MARK: - Changing

    public func setDefault(_ account: AgentAccount?, for agent: AccountAgent) {
        try? store.setDefault(account?.id, for: agent)
        reload()
    }

    public func rename(_ account: AgentAccount, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = accounts.firstIndex(where: { $0.id == account.id && $0.agent == account.agent }) else { return }
        accounts[index].name = trimmed
        save()
    }

    /// Adds the login the person already had (the agent's default folder) as an account, once.
    /// API-key, Bedrock and Vertex setups are not accounts and are left alone.
    public func importExistingLogins() async {
        for agent in AccountAgent.allCases where !accounts(for: agent).contains(where: \.isDefaultFolder) {
            guard let status = await cli.status(agent, environment: ([:], [agent.configVariable])),
                  status.loggedIn, status.isSubscription else { continue }
            reload()
            guard !accounts(for: agent).contains(where: \.isDefaultFolder) else { continue }
            let account = AgentAccount(id: AgentAccount.defaultFolderID, agent: agent, name: status.email ?? agent.displayName,
                                       email: status.email, org: status.org, plan: status.plan, isDefaultFolder: true)
            accounts.insert(account, at: accounts.lastIndex(where: { $0.agent == agent }).map { $0 + 1 } ?? accounts.count)
            signedIn[Self.key(account)] = true
            save()
        }
    }

    /// Prepares a new account's folder (links, seeded settings). It is listed only once
    /// `finishAdd` confirms the sign-in.
    public func beginAdd(_ agent: AccountAgent) throws -> PendingAccount {
        var id = AccountStore.newID()
        while FileManager.default.fileExists(atPath: paths.folder(agent: agent, id: id).path) { id = AccountStore.newID() }
        let account = AgentAccount(id: id, agent: agent, name: agent.displayName, email: nil, org: nil, plan: nil, isDefaultFolder: false)
        try AccountFolder.prepare(account, paths: paths)
        if agent == .claude {
            try AccountFolder.seedClaudeConfig(from: paths.home.appendingPathComponent(".claude.json"),
                                               to: account.folder(in: paths).appendingPathComponent(".claude.json"))
        }
        let base = agent == .claude ? "claude auth login" : "codex login"
        return PendingAccount(account: account, loginCommand: AccountLaunch.command(base, account: account, paths: paths))
    }

    /// Whether the account being added reports a sign-in yet (for a pane without shell
    /// integration, where the login's exit status never arrives).
    public func hasSignedIn(_ pending: PendingAccount) async -> Bool {
        await cli.status(pending.account.agent, environment: AccountLaunch.environment(for: pending.account, paths: paths))?.loggedIn == true
    }

    public func finishAdd(_ pending: PendingAccount, loginSucceeded: Bool) async -> AddOutcome {
        let environment = AccountLaunch.environment(for: pending.account, paths: paths)
        guard loginSucceeded, let status = await cli.status(pending.account.agent, environment: environment), status.loggedIn else {
            // The login may have stored a credential even though it didn't report success (or the
            // status check failed): sign the folder out before it goes, so nothing is left behind.
            if loginSucceeded { await cli.logout(pending.account.agent, environment: environment) }
            discard(pending)
            return .failed
        }
        // Codex reports no organization, so its email alone can't tell two workspaces apart.
        if pending.account.agent == .claude, let existing = accounts(for: pending.account.agent).first(where: {
            $0.email != nil && $0.email == status.email && $0.org == status.org
        }) {
            await cli.logout(pending.account.agent, environment: environment)
            discard(pending)
            return .duplicate(of: existing)
        }
        var account = pending.account
        account.name = status.email ?? account.name
        account.email = status.email
        account.org = status.org
        account.plan = status.plan
        reload()
        accounts.append(account)
        signedIn[Self.key(account)] = true
        save()
        return .added(account)
    }

    /// Signs the account out and drops it from the list. Its folder stays: conversations may have
    /// recorded paths through it. The default-folder login can't be removed this way.
    public func remove(_ account: AgentAccount) async {
        guard !account.isDefaultFolder else { return }
        let environment = AccountLaunch.environment(for: account, paths: paths)
        // Sign out only what is verifiably this account: a status that names someone else means
        // the command would reach a different sign-in, and that one must never be logged out.
        if let status = await cli.status(account.agent, environment: environment), status.loggedIn,
           account.email == nil || status.email == account.email {
            await cli.logout(account.agent, environment: environment)
        }
        reload()
        accounts.removeAll { $0.id == account.id && $0.agent == account.agent }
        if defaults[account.agent] == account.id { try? store.setDefault(nil, for: account.agent) }
        save()
    }

    /// Re-reads which Google account `agy` last signed in as, from its own log.
    public func refreshAntigravitySignIn() async {
        let logs = paths.home.appendingPathComponent(".gemini/antigravity-cli/log")
        let signIn = await Task.detached(priority: .utility) { AntigravitySignIn.read(logDirectory: logs) }.value
        if signIn != antigravitySignIn { antigravitySignIn = signIn }
    }

    /// Re-reads each account's sign-in, email and plan.
    public func refreshStatuses() async {
        await refreshAntigravitySignIn()
        for account in accounts {
            guard let status = await cli.status(account.agent, environment: AccountLaunch.environment(for: account, paths: paths)) else { continue }
            signedIn[Self.key(account)] = status.loggedIn
            guard status.loggedIn, let index = accounts.firstIndex(of: account) else { continue }
            accounts[index].email = status.email ?? accounts[index].email
            accounts[index].org = status.org ?? accounts[index].org
            accounts[index].plan = status.plan ?? accounts[index].plan
        }
        save()
    }

    // MARK: - Limits

    public func limits(for account: AgentAccount) -> UsageLimits? { usageLimits[Self.key(account)] }

    /// "5h 56% → 3:30pm · Wk 79% → Thu 7:30pm", or that the token has expired; nil when unknown.
    public func limitsLine(for account: AgentAccount) -> String? { UsageLimitsFormat.line(limits(for: account)) }

    public var antigravityLimitsLine: String? {
        antigravityLimits == .tokenExpired ? "Token expired — start agy to renew it" : UsageLimitsFormat.line(antigravityLimits)
    }

    /// Asks every account (and agy) at once what is left of its limits.
    public func refreshLimits() async {
        let source = limitsSource, paths = paths
        let keyed = accounts.map { (Self.key($0), $0) }
        async let antigravity = source.antigravityLimits()
        let fetched = await withTaskGroup(of: (String, UsageLimits).self) { group in
            for (key, account) in keyed {
                group.addTask { (key, await source.limits(for: account, paths: paths)) }
            }
            var all: [String: UsageLimits] = [:]
            for await (key, limits) in group { all[key] = limits }
            return all
        }
        // Accounts removed meanwhile drop out with the rest of their state.
        usageLimits = Dictionary(uniqueKeysWithValues: fetched.map { key, limits in (key, Self.merged(limits, over: usageLimits[key]) ?? limits) })
        antigravityLimits = Self.merged(await antigravity, over: antigravityLimits)
    }

    /// A check that got no answer (offline, rate limited) keeps the last numbers rather than
    /// blanking the line; an expired token always shows.
    static func merged(_ new: UsageLimits?, over old: UsageLimits?) -> UsageLimits? {
        if new == .unavailable, case .windows = old { return old }
        return new
    }

    /// Refreshes the limits now and then every `interval` while the caller's task lives. The
    /// endpoints rate-limit, and the agents poll them too, so not more often than this.
    public func keepLimitsFresh(every interval: Duration = .seconds(180)) async {
        while !Task.isCancelled {
            await refreshLimits()
            try? await Task.sleep(for: interval)
        }
    }

    private func discard(_ pending: PendingAccount) {
        try? AccountFolder.discard(pending.account.folder(in: paths))
    }

    private func save() {
        try? store.save(accounts)
        reload()
    }

    // MARK: - Warnings

    /// The key in the shared Claude settings that pins every account to one login, if any.
    public func loginPin(for agent: AccountAgent) -> String? {
        guard agent == .claude, let settings = Self.json(paths.home.appendingPathComponent(".claude/settings.json")) else { return nil }
        for key in ["forceLoginMethod", "forceLoginOrgUUID", "apiKeyHelper"] where settings[key] != nil { return key }
        let env = settings["env"] as? [String: Any] ?? [:]
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"] where env[key] != nil {
            return "env.\(key)"
        }
        return nil
    }

    /// Conversations are shared, so an account whose organization keeps them for less time than
    /// the person's setting deletes everyone's older conversations when it starts.
    public func retentionWarning() -> String? {
        let shared = Self.json(paths.home.appendingPathComponent(".claude/settings.json"))?["cleanupPeriodDays"] as? Int
            ?? ClaudeHookInstaller.defaultRetentionDays
        for account in accounts(for: .claude) {
            let remote = Self.json(account.folder(in: paths).appendingPathComponent("remote-settings.json"))
            let days = remote?["cleanupPeriodDays"] as? Int ?? (remote?["settings"] as? [String: Any])?["cleanupPeriodDays"] as? Int
            if let days, days < shared {
                return "\(account.name)'s organization keeps conversations for \(days) days, less than your \(shared). "
                    + "Starting Claude as \(account.name) deletes shared conversations older than \(days) days."
            }
        }
        return nil
    }

    private static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Watching

    /// Reloads when the launcher changes a default or another Ante window changes the list.
    public func startWatching() {
        guard watcher == nil else { return }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(paths.root.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
