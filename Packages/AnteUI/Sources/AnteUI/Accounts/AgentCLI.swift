// Packages/AnteUI/Sources/AnteUI/Accounts/AgentCLI.swift
import Foundation
import AnteCore
import AnteTerm

/// What an agent says about the sign-in in one folder.
public struct AgentStatus: Equatable, Sendable {
    public var loggedIn: Bool
    public var email: String?
    public var org: String?
    public var plan: String?
    /// A Claude.ai / ChatGPT subscription sign-in, as opposed to an API key or a cloud provider.
    public var isSubscription: Bool

    public init(loggedIn: Bool, email: String?, org: String?, plan: String?, isSubscription: Bool) {
        self.loggedIn = loggedIn
        self.email = email
        self.org = org
        self.plan = plan
        self.isSubscription = isSubscription
    }
}

/// Asks the agents about their sign-ins. Injectable so tests never run a real agent.
public protocol AgentCLIRunning: Sendable {
    func status(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async -> AgentStatus?
    func logout(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async
}

/// The real thing. Claude is asked with `claude auth status --json` through the person's login
/// shell (an app's own PATH rarely has `claude` on it); Codex's sign-in is read from `auth.json`.
public struct AgentCLI: AgentCLIRunning {
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public func status(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async -> AgentStatus? {
        switch agent {
        case .claude:
            guard let output = await Self.runInLoginShell(Self.agentCommand(["claude", "auth", "status", "--json"], environment: environment), environment: environment) else { return nil }
            return Self.parseClaudeStatus(output)
        case .codex:
            let folder = environment.set[agent.configVariable].map { URL(fileURLWithPath: $0) } ?? agent.defaultFolder(home: home)
            return Self.codexStatus(folder: folder)
        }
    }

    public func logout(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async {
        _ = await Self.runInLoginShell(Self.agentCommand(agent == .claude ? ["claude", "auth", "logout"] : ["codex", "logout"], environment: environment),
                                        environment: environment)
    }

    // MARK: - Parsing

    /// The JSON object in `claude auth status --json` output (a profile may print around it).
    static func parseClaudeStatus(_ text: String) -> AgentStatus? {
        // Try each line that opens an object, ending at each later line that closes one.
        let lines = text.components(separatedBy: "\n")
        var found: [String: Any]?
        search: for (i, line) in lines.enumerated() where line.hasPrefix("{") {
            for j in (i..<lines.count).reversed() where lines[j].hasSuffix("}") {
                let candidate = lines[i...j].joined(separator: "\n")
                if let object = (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) as? [String: Any] {
                    found = object
                    break search
                }
            }
        }
        guard let object = found else { return nil }
        let plan = (object["subscriptionType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return AgentStatus(loggedIn: object["loggedIn"] as? Bool ?? false, email: object["email"] as? String,
                           org: object["orgName"] as? String, plan: plan,
                           isSubscription: (object["authMethod"] as? String) == "claude.ai")
    }

    /// Codex keeps its sign-in in `<CODEX_HOME>/auth.json`; a ChatGPT sign-in carries an id token
    /// whose claims hold the email and plan.
    static func codexStatus(folder: URL) -> AgentStatus? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("auth.json")) else {
            return AgentStatus(loggedIn: false, email: nil, org: nil, plan: nil, isSubscription: false)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let tokens = object["tokens"] as? [String: Any]
        guard let idToken = tokens?["id_token"] as? String else {
            let hasKey = (object["OPENAI_API_KEY"] as? String)?.isEmpty == false
            return AgentStatus(loggedIn: hasKey, email: nil, org: nil, plan: nil, isSubscription: false)
        }
        let claims = jwtClaims(idToken) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let plan = (auth?["chatgpt_plan_type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return AgentStatus(loggedIn: true, email: claims["email"] as? String, org: nil, plan: plan, isSubscription: true)
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Running

    /// `words` run as the agent with `environment` applied *on the command line* (`env -u VAR` /
    /// `env VAR=…`), so it holds even when the person's rc files export the variable themselves:
    /// the rc runs first and would override anything set in the process environment.
    /// `/usr/bin/env` reads the same in zsh, bash and fish, and like `command` it skips shell
    /// functions and aliases of the agent.
    static func agentCommand(_ words: [String], environment: (set: [String: String], unset: [String])) -> String {
        var parts = ["/usr/bin/env"]
        for key in environment.unset.sorted() where environment.set[key] == nil { parts += ["-u", ShellQuote.quote(key)] }
        for (key, value) in environment.set.sorted(by: { $0.key < $1.key }) { parts.append(ShellQuote.quote("\(key)=\(value)")) }
        return (parts + words.map(ShellQuote.quote)).joined(separator: " ")
    }

    /// Runs `command` in the person's login shell; nil on failure or after `timeout`.
    /// Interactive so PATH set in rc files counts; stdin is /dev/null. Output is drained as it
    /// arrives, and the wait ends with the shell even if something it started keeps stdout open.
    static func runInLoginShell(_ command: String, environment: (set: [String: String], unset: [String]),
                                shell: String? = nil, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
                                timeout: TimeInterval = 20) async -> String? {
        let shell = shell ?? LoginShell.resolve(environment: baseEnvironment)
        var env = baseEnvironment
        for key in environment.unset { env.removeValue(forKey: key) }
        env.merge(environment.set) { $1 }
        env["TERM"] = "dumb"
        let finalEnvironment = env
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-l", "-i", "-c", command]
                process.environment = finalEnvironment
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                let collected = OutputBuffer()
                output.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                do { try process.run() } catch {
                    output.fileHandleForReading.readabilityHandler = nil
                    return continuation.resume(returning: nil)
                }
                if exited.wait(timeout: .now() + timeout) == .timedOut {
                    process.terminate()
                    _ = exited.wait(timeout: .now() + 2)
                }
                output.fileHandleForReading.readabilityHandler = nil
                // Whatever is still buffered, without waiting for an end of file that a leftover
                // background process may never send.
                let fd = output.fileHandleForReading.fileDescriptor
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                var chunk = [UInt8](repeating: 0, count: 65536)
                while true {
                    let count = read(fd, &chunk, chunk.count)
                    guard count > 0 else { break }
                    collected.append(Data(chunk[0..<count]))
                }
                continuation.resume(returning: process.terminationReason == .uncaughtSignal ? nil : collected.string)
            }
        }
    }
}

/// Output gathered from a pipe's readability handler (another thread) until the process ends.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ more: Data) { lock.withLock { data.append(more) } }
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
