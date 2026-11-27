import XCTest
@testable import AnteCore

final class AccountFolderTests: XCTestCase {
    private var base: URL!
    private var home: URL!
    private var paths: AccountPaths!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent("acctf-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        paths = AccountPaths(root: home.appendingPathComponent(".ante/accounts"), home: home)
        let claude = home.appendingPathComponent(".claude")
        try fm.createDirectory(at: claude.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try fm.createDirectory(at: claude.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try Data("x\n".utf8).write(to: claude.appendingPathComponent("projects/x.jsonl"))
        try Data(#"{"a":1}"#.utf8).write(to: claude.appendingPathComponent("settings.json"))
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: base) }

    private func account(_ agent: AccountAgent = .claude, id: String = "k3x9q2m7") -> AgentAccount {
        AgentAccount(id: id, agent: agent, name: "Work", email: nil, org: nil, plan: nil, isDefaultFolder: false)
    }

    private func linkTarget(_ url: URL) -> String? { try? fm.destinationOfSymbolicLink(atPath: url.path) }

    func testPrepareLinksSharedEntries() throws {
        let acct = account()
        try AccountFolder.prepare(acct, paths: paths)
        let folder = acct.folder(in: paths)
        XCTAssertEqual(linkTarget(folder.appendingPathComponent("projects")), home.appendingPathComponent(".claude/projects").path)
        XCTAssertEqual(linkTarget(folder.appendingPathComponent("settings.json")), home.appendingPathComponent(".claude/settings.json").path)
        XCTAssertNil(linkTarget(folder.appendingPathComponent(".claude.json")))
        XCTAssertNil(linkTarget(folder.appendingPathComponent("sessions")), "the live-process registry is per account")
        // Reading through the link reaches the shared transcript.
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("projects/x.jsonl").path))
    }

    func testPrepareCreatesMissingEmptyTargets() throws {
        let plans = home.appendingPathComponent(".claude/plans")
        XCTAssertFalse(fm.fileExists(atPath: plans.path))
        try AccountFolder.prepare(account(), paths: paths)
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: plans.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: plans.path), [])
        XCTAssertEqual(linkTarget(account().folder(in: paths).appendingPathComponent("plans")), plans.path)
        let history = home.appendingPathComponent(".claude/history.jsonl")
        XCTAssertEqual(try Data(contentsOf: history), Data())
    }

    func testPrepareNeverTouchesExistingTargetContent() throws {
        let settings = home.appendingPathComponent(".claude/settings.json")
        let before = try Data(contentsOf: settings)
        try AccountFolder.prepare(account(), paths: paths)
        try AccountFolder.prepare(account(), paths: paths)
        XCTAssertEqual(try Data(contentsOf: settings), before)
    }

    func testPrepareIsANoOpForDefaultFolderAccount() throws {
        let def = AgentAccount(id: "default", agent: .claude, name: "x", email: nil, org: nil, plan: nil, isDefaultFolder: true)
        try AccountFolder.prepare(def, paths: paths)
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".claude/plans").path))
        XCTAssertEqual(AccountFolder.verify(def, paths: paths), [])
    }

    func testVerifyReportsRealFolderWhereLinkBelongs() throws {
        let acct = account()
        try AccountFolder.prepare(acct, paths: paths)
        let projects = acct.folder(in: paths).appendingPathComponent("projects")
        try fm.removeItem(at: projects)
        try fm.createDirectory(at: projects, withIntermediateDirectories: false)
        XCTAssertEqual(AccountFolder.verify(acct, paths: paths), [AccountFolderProblem(name: "projects", kind: .realItemWhereLinkBelongs)])
        try AccountFolder.prepare(acct, paths: paths)
        XCTAssertNil(linkTarget(projects), "prepare never replaces a real item")
    }

    func testVerifyReportsLinkPointingElsewhere() throws {
        let acct = account()
        try AccountFolder.prepare(acct, paths: paths)
        let skills = acct.folder(in: paths).appendingPathComponent("skills")
        try fm.removeItem(at: skills)
        try fm.createSymbolicLink(atPath: skills.path, withDestinationPath: "/tmp")
        XCTAssertEqual(AccountFolder.verify(acct, paths: paths), [AccountFolderProblem(name: "skills", kind: .linkPointsElsewhere)])
    }

    func testVerifyCleanAfterPrepare() throws {
        try AccountFolder.prepare(account(), paths: paths)
        XCTAssertEqual(AccountFolder.verify(account(), paths: paths), [])
    }

    func testDatabasesLinkedOnlyIfPresent() throws {
        let codex = home.appendingPathComponent(".codex")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data("db".utf8).write(to: codex.appendingPathComponent("state_5.sqlite"))
        let acct = account(.codex, id: "aaaa1111")
        try AccountFolder.prepare(acct, paths: paths)
        let folder = acct.folder(in: paths)
        XCTAssertEqual(linkTarget(folder.appendingPathComponent("state_5.sqlite")), codex.appendingPathComponent("state_5.sqlite").path)
        XCTAssertFalse(fm.fileExists(atPath: codex.appendingPathComponent("goals_1.sqlite").path))
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("goals_") })
        XCTAssertFalse(names.contains("auth.json"))
        XCTAssertTrue(names.contains("sessions"), "Codex conversations are shared")
    }

    func testSharedNamesExcludeIdentity() {
        let claude = AccountFolder.sharedNames(for: .claude)
        XCTAssertTrue(claude.contains("projects"))
        XCTAssertFalse(claude.contains(".claude.json"))
        XCTAssertFalse(claude.contains("sessions"))
        XCTAssertFalse(claude.contains { $0.hasPrefix("remote-settings") || $0.hasPrefix("policy-limits") })
        XCTAssertFalse(AccountFolder.sharedNames(for: .codex).contains("auth.json"))
    }

    func testSeedCopiesOnlyAllowedKeys() throws {
        let source = home.appendingPathComponent(".claude.json")
        let json: [String: Any] = [
            "oauthAccount": ["emailAddress": "x"], "userID": "u", "mcpServers": ["m": ["command": "c"]],
            "hasCompletedOnboarding": true, "theme": "dark",
            "projects": ["/p": ["allowedTools": ["x"], "lastCost": 1, "hasTrustDialogAccepted": true]],
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: source)
        let dest = base.appendingPathComponent("out/.claude.json")
        try AccountFolder.seedClaudeConfig(from: source, to: dest)
        let out = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dest)) as? [String: Any])
        XCTAssertNil(out["oauthAccount"])
        XCTAssertNil(out["userID"])
        XCTAssertNotNil(out["mcpServers"])
        XCTAssertEqual(out["theme"] as? String, "dark")
        let project = try XCTUnwrap((out["projects"] as? [String: Any])?["/p"] as? [String: Any])
        XCTAssertEqual(project["allowedTools"] as? [String], ["x"])
        XCTAssertEqual(project["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertNil(project["lastCost"])
        let mode = try fm.attributesOfItem(atPath: dest.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testSeedWithoutSourceWritesNothing() throws {
        let dest = base.appendingPathComponent("out/.claude.json")
        try AccountFolder.seedClaudeConfig(from: home.appendingPathComponent("missing.json"), to: dest)
        XCTAssertFalse(fm.fileExists(atPath: dest.path))
    }

    func testDiscardDoesNotFollowLinks() throws {
        let acct = account()
        try AccountFolder.prepare(acct, paths: paths)
        try Data("{}".utf8).write(to: acct.folder(in: paths).appendingPathComponent(".claude.json"))
        try AccountFolder.discard(acct.folder(in: paths))
        XCTAssertFalse(fm.fileExists(atPath: acct.folder(in: paths).path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".claude/projects/x.jsonl").path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(".claude/settings.json").path))
    }
}
