// Packages/AnteCore/Tests/AnteCoreTests/AgentsTests.swift
import XCTest
@testable import AnteCore

final class AgentsTests: XCTestCase {
    func testClassifyForegroundCommandLines() {
        XCTAssertEqual(AgentKind.classify(commandLine: ["/bin/zsh", "-l"]), .shell)
        XCTAssertEqual(AgentKind.classify(commandLine: ["-zsh"]), .shell)
        XCTAssertEqual(AgentKind.classify(commandLine: ["/opt/homebrew/bin/claude"]), .claude)
        XCTAssertEqual(AgentKind.classify(commandLine: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]), .claude)
        XCTAssertEqual(AgentKind.classify(commandLine: ["/usr/local/bin/codex", "--full-auto"]), .codex)
        XCTAssertEqual(AgentKind.classify(commandLine: ["python3", "-m", "aider"]), .command, "module form is not matched; aider's own binary is")
        XCTAssertEqual(AgentKind.classify(commandLine: ["/Users/x/.local/bin/aider"]), .aider)
        XCTAssertEqual(AgentKind.classify(commandLine: ["vim", "notes.md"]), .command)
        XCTAssertEqual(AgentKind.classify(commandLine: ["/opt/homebrew/bin/pi", "-c"]), .pi)
        XCTAssertEqual(AgentKind.pi.resumeCommand(sessionID: "0ea51497-613d-4f7e-9de2-8ee99950b074"), "pi --session 0ea51497-613d-4f7e-9de2-8ee99950b074")
        XCTAssertEqual(AgentKind.classify(commandLine: []), .shell)
    }

    func testResumeCommandsAreTemplatedAndValidated() {
        XCTAssertEqual(AgentKind.claude.resumeCommand(sessionID: "3c2b69dc-f7ea-490e-878b-f85b72bbb5ff"), "claude --resume 3c2b69dc-f7ea-490e-878b-f85b72bbb5ff")
        XCTAssertEqual(AgentKind.codex.resumeCommand(sessionID: "019ec6eb-fa35-7a90-885d-23d8ae36f542"), "codex resume 019ec6eb-fa35-7a90-885d-23d8ae36f542")
        XCTAssertNil(AgentKind.claude.resumeCommand(sessionID: "x; rm -rf /"))
        XCTAssertNil(AgentKind.claude.resumeCommand(sessionID: "short"))
        XCTAssertNil(AgentKind.shell.resumeCommand(sessionID: "3c2b69dc-f7ea-490e-878b-f85b72bbb5ff"))
    }

    func testHistoryStoreAppendsNewestFirstAndCaps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-hist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnteSessionHistoryStore(paths: AppPaths(root: root, configRoot: root))
        for i in 0..<(AnteSessionHistoryStore.capacity + 5) {
            try store.append(ClosedSession(name: "s\(i)", workingDirectory: "/tmp", projectPath: "/tmp", lastCommand: nil, agent: .shell,
                                           closedAt: Date(timeIntervalSince1970: Double(i))))
        }
        let all = store.all()
        XCTAssertEqual(all.count, AnteSessionHistoryStore.capacity)
        XCTAssertEqual(all.first?.name, "s\(AnteSessionHistoryStore.capacity + 4)")
        let attrs = try FileManager.default.attributesOfItem(atPath: AppPaths(root: root, configRoot: root).historyFile.path)
        XCTAssertEqual(attrs[.posixPermissions] as? Int, 0o600)
    }

    func testAgentsConfigAndKey() throws {
        XCTAssertEqual(AnteConfig.default.agents.quietSeconds, 8)
        XCTAssertEqual(try ConfigLoader().parse("[agents]\nquiet_seconds = 3").agents.quietSeconds, 3)
        XCTAssertEqual(AnteConfig.default.keys.sessionsBoard.text, "shift+cmd+s")
    }
}
