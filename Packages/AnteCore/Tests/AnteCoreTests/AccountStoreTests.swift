import XCTest
@testable import AnteCore

final class AccountStoreTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("acct-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        root = home.appendingPathComponent(".ante/accounts")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    private var paths: AccountPaths { AccountPaths(root: root, home: home) }

    func testRoundTrip() throws {
        let store = AccountStore(paths: paths)
        let accounts = [
            AgentAccount(id: "default", agent: .claude, name: "me@home.com", email: "me@home.com", org: nil, plan: "Max", isDefaultFolder: true),
            AgentAccount(id: "k3x9q2m7", agent: .claude, name: "Work", email: "me@work.com", org: "Work Inc", plan: "Pro", isDefaultFolder: false),
        ]
        try store.save(accounts)
        XCTAssertEqual(store.load(), accounts)
    }

    func testTabsAndNewlinesInFieldsAreFlattened() throws {
        let store = AccountStore(paths: paths)
        try store.save([AgentAccount(id: "k3x9q2m7", agent: .codex, name: "A\tB\nC", email: nil, org: nil, plan: nil, isDefaultFolder: false)])
        XCTAssertEqual(store.load().first?.name, "A B C")
    }

    func testMalformedLinesAreSkipped() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = """
        # agent\tid\tfolder\tname\temail\torg\tplan
        claude\tk3x9q2m7\t\(root.path)/claude/k3x9q2m7\tWork\tme@work.com\t\tPro
        claude\tbroken
        gemini\tzzzzzzzz\t/x\tNope\t\t\t
        codex\t\t\tDefault\ta@b.c\t\t
        """
        try Data(text.utf8).write(to: paths.accountsFile)
        let loaded = AccountStore(paths: paths).load()
        XCTAssertEqual(loaded.map(\.id), ["k3x9q2m7", "default"])
        XCTAssertEqual(loaded.last?.agent, .codex)
        XCTAssertEqual(loaded.last?.isDefaultFolder, true)
        XCTAssertNil(loaded.first?.org)
    }

    func testDefaultFileRoundTrip() throws {
        let store = AccountStore(paths: paths)
        XCTAssertNil(store.defaultAccountID(for: .claude))
        try store.setDefault("k3x9q2m7", for: .claude)
        XCTAssertEqual(store.defaultAccountID(for: .claude), "k3x9q2m7")
        XCTAssertNil(store.defaultAccountID(for: .codex))
        try store.setDefault(nil, for: .claude)
        XCTAssertNil(store.defaultAccountID(for: .claude))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.defaultFile(for: .claude).path))
    }

    func testNewIDShape() {
        let id = AccountStore.newID()
        XCTAssertNotNil(id.range(of: "^[a-z0-9]{8}$", options: .regularExpression))
        XCTAssertNotEqual(id, AccountStore.newID())
    }

    func testFolderPath() {
        XCTAssertEqual(paths.folder(agent: .claude, id: "abc"), root.appendingPathComponent("claude/abc"))
        let def = AgentAccount(id: "default", agent: .claude, name: "x", email: nil, org: nil, plan: nil, isDefaultFolder: true)
        XCTAssertEqual(def.folder(in: paths), home.appendingPathComponent(".claude"))
        let codexDef = AgentAccount(id: "default", agent: .codex, name: "x", email: nil, org: nil, plan: nil, isDefaultFolder: true)
        XCTAssertEqual(codexDef.folder(in: paths), home.appendingPathComponent(".codex"))
    }

    func testAgentVariables() {
        XCTAssertEqual(AccountAgent.claude.configVariable, "CLAUDE_CONFIG_DIR")
        XCTAssertEqual(AccountAgent.codex.configVariable, "CODEX_HOME")
        XCTAssertEqual(AccountAgent.claude.agentKind, .claude)
        XCTAssertEqual(AccountAgent(agentKind: .codex), .codex)
        XCTAssertNil(AccountAgent(agentKind: .aider))
    }

    func testAppPathsAccountsRootIsInjectable() {
        let app = AppPaths(root: home.appendingPathComponent("support"), configRoot: home.appendingPathComponent("cfg"),
                           accountsRoot: root, home: home)
        XCTAssertEqual(app.accountPaths, paths)
    }
}
