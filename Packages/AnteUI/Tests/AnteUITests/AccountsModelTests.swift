import XCTest
import AnteCore
@testable import AnteUI

/// Stands in for `claude auth status` / `codex` sign-in state, keyed by the folder variable's value
/// ("" = the default folder).
final class FakeAgentCLI: AgentCLIRunning, @unchecked Sendable {
    var statuses: [String: AgentStatus] = [:]
    private(set) var logouts: [(AccountAgent, String)] = []

    private func key(_ agent: AccountAgent, _ env: (set: [String: String], unset: [String])) -> String {
        "\(agent.rawValue):\(env.set[agent.configVariable] ?? "")"
    }

    func status(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async -> AgentStatus? {
        statuses[key(agent, environment)] ?? (environment.set[agent.configVariable] != nil ? fallback : nil)
    }

    func logout(_ agent: AccountAgent, environment: (set: [String: String], unset: [String])) async {
        logouts.append((agent, environment.set[agent.configVariable] ?? ""))
    }

    func set(_ agent: AccountAgent, folder: String = "", _ status: AgentStatus) { statuses["\(agent.rawValue):\(folder)"] = status }
    /// Answers for folders no test named (a new account's folder isn't known in advance).
    var fallback: AgentStatus?
}

@MainActor
final class AccountsModelTests: XCTestCase {
    private var base: URL!
    private var home: URL!
    private var paths: AccountPaths!
    private var cli: FakeAgentCLI!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent("acm-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        paths = AccountPaths(root: home.appendingPathComponent(".ante/accounts"), home: home)
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        cli = FakeAgentCLI()
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: base) }

    private func model() -> AccountsModel { AccountsModel(paths: paths, cli: cli) }

    private let personal = AgentStatus(loggedIn: true, email: "a@x.com", org: "A's Org", plan: "Max", isSubscription: true)

    func testImportAddsLoggedInDefaultFolderAccount() async {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        XCTAssertEqual(m.accounts(for: .claude).map(\.name), ["a@x.com"])
        XCTAssertEqual(m.accounts(for: .claude).first?.isDefaultFolder, true)
        XCTAssertEqual(m.accounts(for: .claude).first?.plan, "Max")
        XCTAssertEqual(m.accounts(for: .codex), [])
        XCTAssertEqual(AccountStore(paths: paths).load().count, 1, "saved for the launcher")
    }

    func testImportSkipsApiKeySetup() async {
        cli.set(.claude, AgentStatus(loggedIn: true, email: nil, org: nil, plan: nil, isSubscription: false))
        let m = model()
        await m.importExistingLogins()
        XCTAssertEqual(m.accounts, [])
    }

    func testImportIsIdempotent() async {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        await m.importExistingLogins()
        XCTAssertEqual(m.accounts.count, 1)
    }

    func testAddCreatesFolderAndLoginCommand() throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        let folder = pending.account.folder(in: paths).path
        XCTAssertEqual(pending.loginCommand, "CLAUDE_CONFIG_DIR=\(folder) claude auth login")
        XCTAssertTrue(fm.fileExists(atPath: folder + "/projects"), "links made before the first run")
        XCTAssertEqual(m.accounts, [], "not listed until the login succeeds")
        XCTAssertEqual(try m.beginAdd(.codex).loginCommand.hasSuffix(" codex login"), true)
    }

    func testFinishAddSuccessListsAccount() async throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        cli.set(.claude, folder: pending.account.folder(in: paths).path,
                AgentStatus(loggedIn: true, email: "w@work.com", org: "Work", plan: "Pro", isSubscription: true))
        let outcome = await m.finishAdd(pending, loginSucceeded: true)
        guard case let .added(account) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(account.name, "w@work.com")
        XCTAssertEqual(m.accounts(for: .claude).map(\.id), [pending.account.id])
    }

    func testFinishAddFailureDiscardsFolder() async throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        let outcome = await m.finishAdd(pending, loginSucceeded: false)
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(fm.fileExists(atPath: pending.account.folder(in: paths).path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".claude/projects").path), "shared targets untouched")
    }

    func testFinishAddNotSignedInDiscards() async throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        let outcome = await m.finishAdd(pending, loginSucceeded: true)   // exit 0 but no login stored
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(fm.fileExists(atPath: pending.account.folder(in: paths).path))
    }

    func testFinishAddDuplicateReported() async throws {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        let pending = try m.beginAdd(.claude)
        cli.set(.claude, folder: pending.account.folder(in: paths).path, personal)
        let outcome = await m.finishAdd(pending, loginSucceeded: true)
        guard case let .duplicate(of: existing) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(existing.isDefaultFolder)
        XCTAssertEqual(m.accounts.count, 1)
        XCTAssertEqual(cli.logouts.map(\.1), [pending.account.folder(in: paths).path], "the duplicate sign-in is signed out")
        XCTAssertFalse(fm.fileExists(atPath: pending.account.folder(in: paths).path))
    }

    func testRemoveKeepsFolder() async throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        cli.set(.claude, folder: pending.account.folder(in: paths).path, AgentStatus(loggedIn: true, email: "w@w", org: nil, plan: nil, isSubscription: true))
        _ = await m.finishAdd(pending, loginSucceeded: true)
        m.setDefault(pending.account, for: .claude)
        await m.remove(pending.account)
        XCTAssertEqual(m.accounts, [])
        XCTAssertEqual(cli.logouts.map(\.1), [pending.account.folder(in: paths).path])
        XCTAssertTrue(fm.fileExists(atPath: pending.account.folder(in: paths).path), "kept: conversations may record paths through it")
        XCTAssertNil(m.defaultAccount(for: .claude), "a removed default is cleared")
    }

    func testRemoveNeverLogsOutADifferentSignIn() async throws {
        let m = model()
        let pending = try m.beginAdd(.claude)
        let folder = pending.account.folder(in: paths).path
        cli.set(.claude, folder: folder, AgentStatus(loggedIn: true, email: "w@w", org: nil, plan: nil, isSubscription: true))
        _ = await m.finishAdd(pending, loginSucceeded: true)
        // Now the folder answers as someone else (e.g. the command reached another sign-in).
        cli.set(.claude, folder: folder, AgentStatus(loggedIn: true, email: "me@main", org: nil, plan: nil, isSubscription: true))
        await m.remove(m.accounts[0])
        XCTAssertEqual(m.accounts, [], "still dropped from the list")
        XCTAssertTrue(cli.logouts.isEmpty, "never signs out an account it didn't verify")
    }

    /// The person's rc exports CLAUDE_CONFIG_DIR: the command must still reach the account's folder.
    func testLoginShellCommandBeatsVariableExportedByRC() async throws {
        let zdot = base.appendingPathComponent("zdot"), bin = base.appendingPathComponent("bin")
        try fm.createDirectory(at: zdot, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try "export CLAUDE_CONFIG_DIR=/rc/chosen\n".write(to: zdot.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let fake = bin.appendingPathComponent("claude")
        try "#!/bin/sh\necho \"CFG=${CLAUDE_CONFIG_DIR-unset} ARGS=$*\"\n".write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let env = ["ZDOTDIR": zdot.path, "PATH": "\(bin.path):/usr/bin:/bin", "HOME": home.path]
        func run(_ environment: (set: [String: String], unset: [String])) async -> String? {
            await AgentCLI.runInLoginShell(AgentCLI.agentCommand(["claude", "auth", "logout"], environment: environment),
                                           environment: environment, shell: "/bin/zsh", baseEnvironment: env, timeout: 10)
        }
        let account = await run((["CLAUDE_CONFIG_DIR": "/acct/it's here"], []))
        XCTAssertEqual(account?.trimmingCharacters(in: .whitespacesAndNewlines), "CFG=/acct/it's here ARGS=auth logout")
        let original = await run(([:], ["CLAUDE_CONFIG_DIR"]))
        XCTAssertEqual(original?.trimmingCharacters(in: .whitespacesAndNewlines), "CFG=unset ARGS=auth logout")
    }

    func testLoginShellTimesOutEvenIfABackgroundJobHoldsOutput() async {
        let started = Date()
        let output = await AgentCLI.runInLoginShell("sleep 30 & echo hi; sleep 30", environment: ([:], []), shell: "/bin/zsh",
                                                    baseEnvironment: ["PATH": "/usr/bin:/bin", "ZDOTDIR": base.path], timeout: 1)
        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testDefaultFolderAccountCannotBeRemoved() async {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        await m.remove(m.accounts[0])
        XCTAssertEqual(m.accounts.count, 1)
    }

    func testNeedsAskingRules() async throws {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        XCTAssertFalse(m.needsAsking(.claude), "one account: never ask")
        let pending = try m.beginAdd(.claude)
        cli.set(.claude, folder: pending.account.folder(in: paths).path, AgentStatus(loggedIn: true, email: "w@w", org: nil, plan: nil, isSubscription: true))
        _ = await m.finishAdd(pending, loginSucceeded: true)
        XCTAssertTrue(m.needsAsking(.claude))
        m.setDefault(m.accounts[0], for: .claude)
        XCTAssertFalse(m.needsAsking(.claude))
        XCTAssertEqual(AccountStore(paths: paths).defaultAccountID(for: .claude), "default", "the launcher sees the same default")
    }

    func testReloadPicksUpDefaultChosenInTheLauncher() async throws {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        try AccountStore(paths: paths).setDefault("default", for: .claude)
        m.reload()
        XCTAssertEqual(m.defaultAccount(for: .claude)?.id, "default")
    }

    func testRename() async {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        m.rename(m.accounts[0], to: "  Personal  ")
        XCTAssertEqual(AccountStore(paths: paths).load().first?.name, "Personal")
        m.rename(m.accounts[0], to: "   ")
        XCTAssertEqual(m.accounts[0].name, "Personal", "an empty name is ignored")
    }

    func testLoginPinDetected() throws {
        try Data(#"{"forceLoginOrgUUID":"x"}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        XCTAssertEqual(model().loginPin(for: .claude), "forceLoginOrgUUID")
        try Data(#"{"env":{"ANTHROPIC_API_KEY":"k"}}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        XCTAssertEqual(model().loginPin(for: .claude), "env.ANTHROPIC_API_KEY")
        try Data(#"{"model":"opus"}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        XCTAssertNil(model().loginPin(for: .claude))
    }

    func testRetentionWarning() async throws {
        cli.set(.claude, personal)
        let m = model()
        await m.importExistingLogins()
        let pending = try m.beginAdd(.claude)
        cli.set(.claude, folder: pending.account.folder(in: paths).path, AgentStatus(loggedIn: true, email: "w@w", org: nil, plan: nil, isSubscription: true))
        _ = await m.finishAdd(pending, loginSucceeded: true)
        try Data(#"{"cleanupPeriodDays":90}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        XCTAssertNil(m.retentionWarning())
        try Data(#"{"cleanupPeriodDays":7}"#.utf8).write(to: pending.account.folder(in: paths).appendingPathComponent("remote-settings.json"))
        let warning = try XCTUnwrap(m.retentionWarning())
        XCTAssertTrue(warning.contains("w@w") && warning.contains("7") && warning.contains("90"), warning)
    }

    func testCodexStatusFromAuthFile() throws {
        let folder = base.appendingPathComponent("codexhome")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = #"{"email":"c@x.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#
        let jwt = "e30." + Data(payload.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + ".sig"
        try Data(#"{"auth_mode":"chatgpt","tokens":{"id_token":"JWT"}}"#.replacingOccurrences(of: "JWT", with: jwt).utf8)
            .write(to: folder.appendingPathComponent("auth.json"))
        XCTAssertEqual(AgentCLI.codexStatus(folder: folder),
                       AgentStatus(loggedIn: true, email: "c@x.com", org: nil, plan: "Plus", isSubscription: true))
        try Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#.utf8).write(to: folder.appendingPathComponent("auth.json"))
        XCTAssertEqual(AgentCLI.codexStatus(folder: folder)?.isSubscription, false)
        try fm.removeItem(at: folder.appendingPathComponent("auth.json"))
        XCTAssertEqual(AgentCLI.codexStatus(folder: folder)?.loggedIn, false)
    }

    func testClaudeStatusParsing() {
        let text = """
        noise from a profile
        {"loggedIn":true,"authMethod":"claude.ai","email":"a@x.com","orgName":"Org","subscriptionType":"max","planTier":"max_20x"}
        """
        XCTAssertEqual(AgentCLI.parseClaudeStatus(text), AgentStatus(loggedIn: true, email: "a@x.com", org: "Org", plan: "Max", isSubscription: true))
        XCTAssertEqual(AgentCLI.parseClaudeStatus(#"{"loggedIn":false,"authMethod":"none"}"#)?.loggedIn, false)
        XCTAssertNil(AgentCLI.parseClaudeStatus("not json"))
        let noisy = "prompt {weird} noise\n{\n  \"loggedIn\": true,\n  \"authMethod\": \"claude.ai\"\n}\ntrailing }"
        XCTAssertEqual(AgentCLI.parseClaudeStatus(noisy)?.loggedIn, true)
    }
}
