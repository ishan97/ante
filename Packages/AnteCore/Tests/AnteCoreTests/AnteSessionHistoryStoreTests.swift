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
}
