// Packages/AnteCore/Tests/AnteCoreTests/AnteSessionHistoryStoreTests.swift
import XCTest
@testable import AnteCore

final class AnteSessionHistoryStoreTests: XCTestCase {
    func testOnlyAgentSessionsAreKeptEvenFromOlderFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-hist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = AnteSessionHistoryStore(paths: paths)

        // A file written by an older Ante that still filed shells.
        let old = [ClosedSession(name: "zsh", workingDirectory: "/tmp", projectPath: "/tmp", lastCommand: "ls", agent: .shell),
                   ClosedSession(name: "build", workingDirectory: "/tmp", projectPath: "/tmp", lastCommand: "make", agent: .command)]
        try FileManager.default.createDirectory(at: paths.historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.anteHistory.encode(old).write(to: paths.historyFile)
        XCTAssertTrue(store.all().isEmpty, "shells and commands from before are hidden")

        try store.append(contentsOf: [
            ClosedSession(name: "api", workingDirectory: "/work/api", projectPath: "/work/api", lastCommand: "claude", agent: .claude),
            ClosedSession(name: "scratch", workingDirectory: "/tmp", projectPath: "/tmp", lastCommand: nil, agent: .shell),
        ])
        XCTAssertEqual(store.all().map(\.name), ["api"], "only the agent session is filed")
    }

    /// Picking a closed agent session up again never opens a bare shell: the exact conversation
    /// when its id was known, else the agent's picker (entries from before the id was kept).
    func testClosedAgentSessionsResume() throws {
        func closed(_ agent: AgentKind, _ id: String?) -> ClosedSession {
            ClosedSession(name: "x", workingDirectory: "/w", projectPath: "/w", lastCommand: nil, agent: agent, agentSessionID: id)
        }
        XCTAssertEqual(closed(.claude, "0b6e2a1c-7f0e-4c39-9d8a-3c1f7e2b9a10").asPastSession.resumeCommand,
                       "claude --resume 0b6e2a1c-7f0e-4c39-9d8a-3c1f7e2b9a10")
        XCTAssertEqual(closed(.codex, nil).asPastSession.resumeCommand, "codex resume")
        XCTAssertEqual(closed(.claude, "x; rm -rf ~").resumeCommand, "claude --resume", "an unsafe id is never typed")
        // An entry written before the id was kept decodes, and resumes through the picker.
        let legacy = #"[{"id":"1","name":"api","workingDirectory":"/w","projectPath":"/w","agent":"claude","closedAt":"2026-10-01T10:00:00Z"}]"#
        let decoded = try JSONDecoder.anteHistory.decode([ClosedSession].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.first?.agentSessionID)
        XCTAssertEqual(decoded.first?.asPastSession.resumeCommand, "claude --resume")
    }
}
