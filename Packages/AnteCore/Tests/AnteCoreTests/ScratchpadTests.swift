// Packages/AnteCore/Tests/AnteCoreTests/ScratchpadTests.swift
import XCTest
@testable import AnteCore

final class ScratchpadTests: XCTestCase {
    func testRoundTripAndPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-pad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScratchpadStore(file: root.appendingPathComponent("scratchpad.json"))
        XCTAssertEqual(store.load(), Scratchpad(), "missing file: empty pad")
        var pad = Scratchpad(items: [TodoItem(text: "ship 1.0"), TodoItem(text: "call mum", isDone: true, doneAt: Date())], notes: "remember the milk")
        try store.save(pad)
        let back = store.load()
        XCTAssertEqual(back.items.map(\.text), ["ship 1.0", "call mum"])
        XCTAssertEqual(back.notes, "remember the milk")
        XCTAssertEqual(back.openItems.count, 1)
        XCTAssertEqual(back.doneItems.first?.text, "call mum")
        let perms = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        pad.notes = ""
        try store.save(pad)
        XCTAssertEqual(store.load().notes, "")
    }

    func testOlderFilesWithoutNotesDecode() throws {
        let pad = try JSONDecoder.anteScratchpad.decode(Scratchpad.self, from: Data(#"{"items":[]}"#.utf8))
        XCTAssertEqual(pad.notes, "")
    }
}
