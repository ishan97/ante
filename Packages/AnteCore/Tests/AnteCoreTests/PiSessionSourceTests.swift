// Packages/AnteCore/Tests/AnteCoreTests/PiSessionSourceTests.swift
import XCTest
@testable import AnteCore

final class PiSessionSourceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-pi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(_ lines: [String], to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    func testScanReadsHeaderTitleSlotPromptsAndBranches() throws {
        try write([
            #"{"type":"session","version":3,"id":"0ea51497-613d-4f7e-9de2-8ee99950b074","timestamp":"2026-09-01T10:00:00.000Z","cwd":"/Users/t/proj"}"#,
            #"{"type":"message","id":"e1","parentId":null,"timestamp":"2026-09-01T10:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}],"timestamp":1}}"#,
            #"{"type":"message","id":"e2","parentId":"e1","timestamp":"2026-09-01T10:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Looking."}]}}"#,
            #"{"type":"message","id":"e3","parentId":"e2","timestamp":"2026-09-01T10:05:00.000Z","message":{"role":"user","content":[{"type":"text","text":"and the logout"}]}}"#,
        ], to: "--Users-t-proj--/2026-09-01T10-00-00-000Z_0ea51497.jsonl")
        try write([
            #"{"type":"title","title":"Renamed by /title"}"#,
            #"{"type":"session","version":3,"id":"ab12cd34-0000-4000-8000-000000000002","timestamp":"2026-09-02T09:00:00Z","cwd":"/Users/t/other","parentSession":"/Users/t/.pi/agent/sessions/x/y.jsonl"}"#,
            #"{"type":"message","id":"e1","parentId":null,"timestamp":"2026-09-02T09:00:01Z","message":{"role":"user","content":"plain string prompt"}}"#,
        ], to: "--Users-t-other--/2026-09-02T09-00-00-000Z_ab12cd34.jsonl")
        try write(["not a session at all"], to: "--Users-t-other--/junk.jsonl")

        let source = PiSessionSource(root: root)
        let sessions = source.scan()
        XCTAssertEqual(sessions.count, 2)
        let first = try XCTUnwrap(sessions.first { $0.id == "0ea51497-613d-4f7e-9de2-8ee99950b074" })
        XCTAssertEqual(first.title, "Fix the login bug", "no title anywhere: the first real prompt")
        XCTAssertEqual(first.projectPath, "/Users/t/proj")
        XCTAssertEqual(first.agent, .pi)
        XCTAssertEqual(first.resumeCommand, "pi --session 0ea51497-613d-4f7e-9de2-8ee99950b074")
        XCTAssertNil(first.detail)
        let second = try XCTUnwrap(sessions.first { $0.id == "ab12cd34-0000-4000-8000-000000000002" })
        XCTAssertEqual(second.title, "Renamed by /title", "the title slot line wins over the prompt")
        XCTAssertEqual(second.detail, "branch", "a session branched from another is marked")

        let events = source.events()
        XCTAssertEqual(events.count, 3, "one per user prompt across both files")
        XCTAssertEqual(Set(events.map(\.sessionID)).count, 2)
        XCTAssertTrue(events.allSatisfy { $0.agent == .pi })
    }
}
