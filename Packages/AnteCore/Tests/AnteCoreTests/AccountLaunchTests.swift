import XCTest
@testable import AnteCore

final class AccountLaunchTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/me")
    private var paths: AccountPaths { AccountPaths(root: home.appendingPathComponent(".ante/accounts"), home: home) }

    private func account(_ agent: AccountAgent, id: String, isDefault: Bool = false) -> AgentAccount {
        AgentAccount(id: id, agent: agent, name: "n", email: nil, org: nil, plan: nil, isDefaultFolder: isDefault)
    }

    func testNoAccountLeavesCommandAlone() {
        XCTAssertEqual(AccountLaunch.command("claude --resume abcdefgh", account: nil, paths: paths), "claude --resume abcdefgh")
    }

    func testPrefixDefaultAccount() {
        XCTAssertEqual(AccountLaunch.command("claude --resume abcdefgh", account: account(.claude, id: "default", isDefault: true), paths: paths),
                       "ANTE_ACCOUNT=default claude --resume abcdefgh")
    }

    func testPrefixFolderAccount() {
        XCTAssertEqual(AccountLaunch.command("claude --resume abcdefgh", account: account(.claude, id: "k3x9q2m7"), paths: paths),
                       "CLAUDE_CONFIG_DIR=/Users/me/.ante/accounts/claude/k3x9q2m7 claude --resume abcdefgh")
    }

    func testPrefixCodex() {
        XCTAssertEqual(AccountLaunch.command("codex resume abcdefgh", account: account(.codex, id: "aaaa1111"), paths: paths),
                       "CODEX_HOME=/Users/me/.ante/accounts/codex/aaaa1111 codex resume abcdefgh")
    }

    func testPrefixQuotesOddPaths() {
        let odd = AccountPaths(root: URL(fileURLWithPath: "/Users/me/My Stuff/accounts"), home: home)
        XCTAssertEqual(AccountLaunch.prefix(for: account(.claude, id: "k3x9q2m7"), paths: odd),
                       "CLAUDE_CONFIG_DIR='/Users/me/My Stuff/accounts/claude/k3x9q2m7' ")
    }

    func testEnvironmentForFolderAndDefault() {
        let folder = AccountLaunch.environment(for: account(.codex, id: "aaaa1111"), paths: paths)
        XCTAssertEqual(folder.set, ["CODEX_HOME": "/Users/me/.ante/accounts/codex/aaaa1111"])
        XCTAssertEqual(folder.unset, [])
        let def = AccountLaunch.environment(for: account(.claude, id: "default", isDefault: true), paths: paths)
        XCTAssertEqual(def.set, [:])
        XCTAssertEqual(def.unset, ["CLAUDE_CONFIG_DIR"])
    }

    func testSavedPaneDecodesWithoutAccount() throws {
        let json = #"{"workingDirectory":"file:///tmp/p/","agent":"claude","agentSessionID":"abcdefgh-1"}"#
        XCTAssertNil(try JSONDecoder().decode(SavedPane.self, from: Data(json.utf8)).accountID)
    }

    func testSavedPaneRoundTripsAccount() throws {
        let pane = SavedPane(workingDirectory: URL(fileURLWithPath: "/p"), agent: .claude, agentSessionID: "abcdefgh-1", accountID: "k3x9q2m7")
        let decoded = try JSONDecoder().decode(SavedPane.self, from: JSONEncoder().encode(pane))
        XCTAssertEqual(decoded.accountID, "k3x9q2m7")
        XCTAssertEqual(decoded, pane)
    }

    func testClosedSessionCarriesAccountIntoPastSession() throws {
        let closed = ClosedSession(name: "x", workingDirectory: "/p", projectPath: "/p", lastCommand: nil, agent: .claude,
                                   agentSessionID: "abcdefgh-1", accountID: "k3x9q2m7")
        XCTAssertEqual(closed.asPastSession.accountID, "k3x9q2m7")
        let old = #"[{"id":"1","name":"x","workingDirectory":"/p","projectPath":"/p","agent":"claude","closedAt":0}]"#
        XCTAssertNil(try JSONDecoder().decode([ClosedSession].self, from: Data(old.utf8)).first?.accountID)
    }
}
