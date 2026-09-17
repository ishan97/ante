// Packages/AnteCore/Tests/AnteCoreTests/KeyBindingTests.swift
import XCTest
@testable import AnteCore

final class KeyBindingTests: XCTestCase {
    func testParseAndCanonicalForm() throws {
        let b = try KeyBinding.parse("Shift+CMD+p")
        XCTAssertEqual(b, KeyBinding(key: "p", modifiers: [.cmd, .shift]))
        XCTAssertEqual(b.text, "shift+cmd+p")
        XCTAssertEqual(b.display, "⇧⌘P")
        XCTAssertEqual(try KeyBinding.parse("ctrl+alt+up").display, "⌃⌥↑")
        XCTAssertEqual(try KeyBinding.parse("opt+space").text, "alt+space")
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try KeyBinding.parse("k"))
        XCTAssertThrowsError(try KeyBinding.parse("cmd+"))
        XCTAssertThrowsError(try KeyBinding.parse("hyper+k"))
        XCTAssertThrowsError(try KeyBinding.parse("cmd+pageup"))
    }

    func testCursorDefaultsAndOverrides() throws {
        let d = AnteConfig.default.cursor
        XCTAssertEqual(d.style, .block)
        XCTAssertFalse(d.blink)
        let c = try ConfigLoader().parse("[cursor]\nstyle = \"bar\"\nblink = true")
        XCTAssertEqual(c.cursor.style, .bar)
        XCTAssertTrue(c.cursor.blink)
        XCTAssertThrowsError(try ConfigLoader().parse("[cursor]\nstyle = \"beam\""))
    }

    func testDefaultsAndOverrides() throws {
        let d = AnteConfig.default.keys
        XCTAssertEqual(d.clearPane.text, "cmd+k")
        XCTAssertEqual(d.commandPalette.text, "shift+cmd+p")
        XCTAssertEqual(d.all.count, 13)
        XCTAssertEqual(d.scratchpad.text, "shift+cmd+t")
        XCTAssertEqual(d.insertFile.text, "shift+cmd+o")
        XCTAssertEqual(d.splitLeft.text, "alt+cmd+d")
        XCTAssertEqual(d.splitUp.text, "alt+shift+cmd+d")
        let config = try ConfigLoader().parse("[keys]\nclear_pane = \"cmd+l\"\ncommand_palette = \"cmd+k\"")
        XCTAssertEqual(config.keys.clearPane.text, "cmd+l")
        XCTAssertEqual(config.keys.commandPalette.text, "cmd+k")
        XCTAssertEqual(config.keys.find.text, "cmd+f", "untouched keys keep defaults")
        XCTAssertThrowsError(try ConfigLoader().parse("[keys]\nfind = \"banana\""))
    }
}
