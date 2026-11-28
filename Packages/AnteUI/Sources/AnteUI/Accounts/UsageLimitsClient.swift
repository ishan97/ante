import Foundation
import AnteCore

/// Asks the providers what is left of each account's limits. Injectable so tests never read the
/// Keychain or reach the network.
public protocol UsageLimitsFetching: Sendable {
    func limits(for account: AgentAccount, paths: AccountPaths) async -> UsageLimits
    /// Antigravity's one sign-in; nil when agy has never signed in.
    func antigravityLimits() async -> UsageLimits?
}

/// The real thing: reads the token each agent saved (Keychain through `/usr/bin/security`, the
/// tool the agents stored them with, so macOS doesn't ask; Codex from `auth.json`) and calls the
/// endpoint behind the agent's own `/usage` screen.
///
/// A Claude access token lasts about 8 hours, so an account not used today has an expired one.
/// Ante renews it the way a second Claude Code would (see `renewClaude`). Other agents' expired
/// tokens are reported, not renewed.
public struct UsageLimitsClient: UsageLimitsFetching {
    public let home: URL
    private let session: URLSession
    private let rejected = RejectedRefreshTokens()

    public init(home: URL) {
        self.home = home
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func limits(for account: AgentAccount, paths: AccountPaths) async -> UsageLimits {
        switch account.agent {
        case .claude:
            let service = Self.claudeService(account, paths: paths)
            guard let owner = await Self.keychainAccount(service: service),
                  let value = await Self.keychain(service: service, account: owner),
                  var token = UsageLimitsParser.claudeToken(value) else { return .unavailable }
            if token.isExpired(now: Date(), margin: ClaudeRenewal.margin) {
                switch await renewClaude(account, paths: paths, sawAccessToken: token.accessToken) {
                case let .renewed(fresh): token = fresh
                case .busy: return .unavailable
                case .failed: if token.isExpired(now: Date()) { return .tokenExpired }   // else: still good for now
                }
            }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            return await fetch(request, token: token, parse: UsageLimitsParser.claudeLimits)
        case .codex:
            let file = account.folder(in: paths).appendingPathComponent("auth.json")
            guard let data = try? Data(contentsOf: file), let token = UsageLimitsParser.codexToken(data) else { return .unavailable }
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            if let id = token.accountID { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
            request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
            return await fetch(request, token: token, parse: UsageLimitsParser.codexLimits)
        }
    }

    public func antigravityLimits() async -> UsageLimits? {
        guard let value = await Self.keychain(service: "gemini", account: "antigravity"),
              let token = UsageLimitsParser.antigravityToken(value) else { return nil }
        // The host and client name agy uses; Google refuses the call from anything else.
        var request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.5.19 darwin/\(Self.architecture)", forHTTPHeaderField: "User-Agent")
        return await fetch(request, token: token, parse: UsageLimitsParser.antigravityLimits)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }

    private func fetch(_ request: URLRequest, token: UsageToken, parse: (Data) -> [UsageWindow]?) async -> UsageLimits {
        if token.isExpired(now: Date()) { return .tokenExpired }
        var request = request
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request) else { return .unavailable }
        if (response as? HTTPURLResponse)?.statusCode == 401 { return .tokenExpired }
        return parse(data).map(UsageLimits.windows) ?? .unavailable
    }

    // MARK: - Renewing Claude

    enum Renewal: Equatable {
        case renewed(UsageToken)
        /// Another process holds Claude Code's renewal lock; try again next time.
        case busy
        /// Not renewed: an item shape Ante leaves alone, a refused token, or no answer.
        case failed
    }

    static func claudeService(_ account: AgentAccount, paths: AccountPaths) -> String {
        UsageLimitsParser.claudeKeychainService(configFolder: account.isDefaultFolder ? nil : account.folder(in: paths).path)
    }

    /// Renews an expired Claude sign-in exactly as Claude Code does, so to any running Claude
    /// it looks like another Claude Code renewing:
    /// 1. take Claude Code's renewal lock (`<config>/.oauth_refresh.lock`, and the older
    ///    `<config>.lock`); if another process holds it, give up for now;
    /// 2. read the credentials again under the lock: a different access token means someone
    ///    renewed already, so use theirs;
    /// 3. only for an item in the plain one-entry shape, post the refresh token to Claude Code's
    ///    token endpoint with its client id and scopes;
    /// 4. write the item back with only the three token fields changed, and read it back.
    ///
    /// `force` renews a token that is still valid (only for checking the whole path by hand).
    ///
    /// Runs detached: once the refresh token is posted it is spent, so the write must not be
    /// lost because the view that asked went away and its task was cancelled.
    func renewClaude(_ account: AgentAccount, paths: AccountPaths, sawAccessToken: String?, force: Bool = false) async -> Renewal {
        let client = self
        return await Task.detached(priority: .utility) {
            await client.renewUnderLock(account, paths: paths, sawAccessToken: sawAccessToken, force: force)
        }.value
    }

    private func renewUnderLock(_ account: AgentAccount, paths: AccountPaths, sawAccessToken: String?, force: Bool) async -> Renewal {
        let service = Self.claudeService(account, paths: paths)
        // Everything the write needs is checked before the refresh token is spent.
        guard let owner = await Self.keychainAccount(service: service),
              ClaudeRenewal.isQuotable(owner), ClaudeRenewal.isQuotable(service) else { return .failed }
        guard let lock = RenewalLock.take(configFolder: account.folder(in: paths)) else { return .busy }
        defer { lock.release() }
        guard let current = await Self.keychain(service: service, account: owner),
              let token = UsageLimitsParser.claudeToken(current) else { return .failed }
        if let sawAccessToken, token.accessToken != sawAccessToken {
            return token.isExpired(now: Date(), margin: ClaudeRenewal.margin) ? .failed : .renewed(token)
        }
        if !force && !token.isExpired(now: Date(), margin: ClaudeRenewal.margin) { return .renewed(token) }
        guard ClaudeRenewal.isPlainItem(credentials: current),
              let body = ClaudeRenewal.requestBody(credentials: current),
              let refreshToken = ClaudeRenewal.refreshToken(credentials: current),
              await !rejected.contains(refreshToken) else { return .failed }
        // Held past Claude Code's 60 s stale limit (the Mac slept, a Keychain dialog waited) and
        // taken over: that renewal is Claude Code's now.
        guard lock.isStillHeld else { return .busy }
        var request = URLRequest(url: ClaudeRenewal.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await session.data(for: request) else { return .failed }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Refused for good (signed out elsewhere): don't send this token again every few minutes.
        if [400, 401, 403].contains(status) { await rejected.insert(refreshToken) }
        guard status == 200,
              let renewed = ClaudeRenewal.renewed(credentials: current, reply: data, now: Date()),
              let fresh = UsageLimitsParser.claudeToken(renewed) else { return .failed }
        // If someone else saved a renewal meanwhile, theirs stays (as Claude Code does).
        if let saved = await Self.keychain(service: service, account: owner), ClaudeRenewal.refreshToken(credentials: saved) != refreshToken {
            return UsageLimitsParser.claudeToken(saved).map(Renewal.renewed) ?? .failed
        }
        // The old refresh token is spent now: the write must land, so try it twice.
        for _ in 0..<2 {
            if await Self.writeKeychain(service: service, account: owner, value: renewed),
               await Self.keychain(service: service, account: owner).flatMap(UsageLimitsParser.claudeToken)?.accessToken == fresh.accessToken {
                return .renewed(fresh)
            }
        }
        return .failed
    }

    // MARK: - Keychain

    /// A generic password's value, or nil when there is none.
    static func keychain(service: String, account: String? = nil) async -> String? {
        let output = await security(["find-generic-password"] + (account.map { ["-a", $0] } ?? []) + ["-s", service, "-w"])
        let value = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    /// The item's account attribute. Claude Code saves and reads it under the person's user
    /// name, so that is tried first; any other item with the service is a fallback.
    static func keychainAccount(service: String) async -> String? {
        let user = NSUserName()
        if await security(["find-generic-password", "-a", user, "-s", service]) != nil { return user }
        guard let attributes = await security(["find-generic-password", "-s", service]) else { return nil }
        for line in attributes.split(separator: "\n") where line.contains("\"acct\"<blob>=\"") {
            guard let start = line.range(of: "<blob>=\"")?.upperBound, line.hasSuffix("\"") else { continue }
            return String(line[start..<line.index(before: line.endIndex)])
        }
        return nil
    }

    /// Updates the item the way Claude Code does: `security -i` reading the command from stdin
    /// (so the secret is never on a command line), the value hex-encoded. An item too long for
    /// one `security -i` line goes on the command line instead, which is Claude Code's own
    /// fallback for the same case.
    static func writeKeychain(service: String, account: String, value: String) async -> Bool {
        if let command = ClaudeRenewal.stdinCommand(account: account, service: service, value: value) {
            return await security(["-i"], input: Data((command + "\n").utf8)) != nil
        }
        return await security(["add-generic-password", "-U", "-a", account, "-s", service, "-X", ClaudeRenewal.hex(value)]) != nil
    }

    /// Runs `/usr/bin/security`; its output, or nil when it fails.
    private static func security(_ arguments: [String], input: Data? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                let stdin = Pipe()
                process.standardInput = input == nil ? FileHandle.nullDevice : stdin
                do { try process.run() } catch { return continuation.resume(returning: nil) }
                // A Keychain that asks to be unlocked must not hold the renewal lock for long.
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
                defer { watchdog.cancel() }
                if let input {
                    // `write(contentsOf:)` throws on a closed pipe where `write(_:)` would raise.
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}

/// Refresh tokens Anthropic refused, so they are not sent again; a new sign-in brings a new one.
actor RejectedRefreshTokens {
    private var tokens: Set<String> = []
    func contains(_ token: String) -> Bool { tokens.contains(token) }
    func insert(_ token: String) { tokens.insert(token) }
}

/// Claude Code's renewal lock: proper-lockfile directories, created with `mkdir` (atomic). Claude
/// Code counts one as stale after 60 s and won't take over one without its owner record; Ante
/// holds it for one request (at most 20 s) and never waits for or breaks someone else's.
struct RenewalLock {
    private let held: [(path: String, inode: ino_t)]

    static func take(configFolder: URL) -> RenewalLock? {
        let primary = configFolder.appendingPathComponent(ClaudeRenewal.lockName).path
        let legacy = configFolder.resolvingSymlinksInPath().path + ".lock"
        guard let first = make(primary) else { return nil }
        guard let second = make(legacy) else {
            remove(first)
            return nil
        }
        return RenewalLock(held: [second, first])
    }

    /// Whether both directories are still the ones this lock created.
    var isStillHeld: Bool {
        held.allSatisfy { item in
            var info = stat()
            return lstat(item.path, &info) == 0 && info.st_ino == item.inode
        }
    }

    /// Removes only the directories this lock created: if one was replaced meanwhile (another
    /// process judged it stale and took it), that one is theirs and stays.
    func release() {
        for item in held { Self.remove(item) }
    }

    private static func make(_ path: String) -> (path: String, inode: ino_t)? {
        guard mkdir(path, 0o755) == 0 else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (path, info.st_ino)
    }

    private static func remove(_ item: (path: String, inode: ino_t)) {
        var info = stat()
        guard lstat(item.path, &info) == 0, info.st_ino == item.inode else { return }
        rmdir(item.path)
    }
}
