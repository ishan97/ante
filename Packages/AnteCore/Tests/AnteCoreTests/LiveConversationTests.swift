import XCTest
@testable import AnteCore

final class LiveConversationTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    func testClaudeRegistryParsed() throws {
        try Data(#"{"pid":123,"sessionId":"s1-abcdef","status":"busy","cwd":"/p"}"#.utf8).write(to: dir.appendingPathComponent("sessions/123.json"))
        XCTAssertEqual(LiveConversationReader.claude(pid: 123, configDirectory: dir), LiveConversation(id: "s1-abcdef", isBusy: true))
    }

    func testClaudeRegistryIdle() throws {
        try Data(#"{"sessionId":"s2-abcdef","status":"idle"}"#.utf8).write(to: dir.appendingPathComponent("sessions/9.json"))
        XCTAssertEqual(LiveConversationReader.claude(pid: 9, configDirectory: dir), LiveConversation(id: "s2-abcdef", isBusy: false))
    }

    func testClaudeRegistryMissing() {
        XCTAssertNil(LiveConversationReader.claude(pid: 5, configDirectory: dir))
    }

    func testClaudeRegistryRejectsUnsafeID() throws {
        try Data(#"{"sessionId":"; rm -rf /","status":"idle"}"#.utf8).write(to: dir.appendingPathComponent("sessions/7.json"))
        XCTAssertNil(LiveConversationReader.claude(pid: 7, configDirectory: dir))
    }

    func testCodexIDFromRolloutPath() {
        let files = ["/dev/ttys001", "/Users/me/.codex/log/codex-tui.log",
                     "/Users/me/.codex/sessions/2026/11/27/rollout-2026-11-27T10-00-00-0199aaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"]
        XCTAssertEqual(LiveConversationReader.codexID(openFiles: files), "0199aaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertNil(LiveConversationReader.codexID(openFiles: ["/tmp/rollout-notes.jsonl"]))
    }

    func testOpenFilesIncludesOpenedFile() throws {
        let file = dir.appendingPathComponent("held.txt")
        try Data("x".utf8).write(to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 3<'\(file.path)'; exec sleep 5"]
        try process.run()
        defer { process.terminate() }
        let deadline = Date().addingTimeInterval(3)
        var files: [String] = []
        while Date() < deadline {
            files = LiveConversationReader.openFiles(pid: process.processIdentifier)
            if files.contains(where: { $0.hasSuffix("/held.txt") }) { break }
            usleep(50_000)
        }
        XCTAssertTrue(files.contains { $0.hasSuffix("/held.txt") }, "\(files)")
    }

    private func account(_ id: String, isDefault: Bool = false, agent: AccountAgent = .claude) -> AgentAccount {
        AgentAccount(id: id, agent: agent, name: id, email: nil, org: nil, plan: nil, isDefaultFolder: isDefault)
    }

    func testResolverMatchesFolder() {
        let paths = AccountPaths(root: URL(fileURLWithPath: "/h/.ante/accounts"), home: URL(fileURLWithPath: "/h"))
        let accounts = [account("default", isDefault: true), account("k3x9q2m7")]
        XCTAssertEqual(AccountResolver.account(for: ["CLAUDE_CONFIG_DIR": "/h/.ante/accounts/claude/k3x9q2m7/"], agent: .claude,
                                               accounts: accounts, paths: paths)?.id, "k3x9q2m7")
        XCTAssertNil(AccountResolver.account(for: ["CLAUDE_CONFIG_DIR": "/elsewhere"], agent: .claude, accounts: accounts, paths: paths))
    }

    func testResolverNoVariableIsDefault() {
        let paths = AccountPaths(root: URL(fileURLWithPath: "/h/.ante/accounts"), home: URL(fileURLWithPath: "/h"))
        let accounts = [account("default", isDefault: true), account("k3x9q2m7")]
        XCTAssertEqual(AccountResolver.account(for: [:], agent: .claude, accounts: accounts, paths: paths)?.id, "default")
        XCTAssertNil(AccountResolver.account(for: [:], agent: .codex, accounts: accounts, paths: paths), "no Codex default-folder account known")
    }
}
