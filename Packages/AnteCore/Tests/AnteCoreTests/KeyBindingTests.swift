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
        XCTAssertEqual(d.all.count, 17)
        XCTAssertEqual(d.toggleFullscreen.text, "cmd+return")
        XCTAssertEqual(d.fontBigger.text, "cmd+=")
        XCTAssertEqual(d.fontSmaller.text, "cmd+-")
        XCTAssertEqual(d.fontReset.text, "cmd+0")
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

extension KeyBindingTests {
    func testWindowSectionDefaultsAndOverrides() throws {
        let d = AnteConfig.default.window
        XCTAssertEqual(d.width, 0.8)
        XCTAssertEqual(d.height, 0.8)
        XCTAssertTrue(d.isFixed)
        let c = try ConfigLoader().parse("[window]\nwidth = 0.5\nheight = 1")
        XCTAssertEqual(c.window.width, 0.5)
        XCTAssertEqual(c.window.height, 1)
        XCTAssertFalse(try ConfigLoader().parse("[window]\nwidth = 0").window.isFixed, "0 means remember the last size")
        XCTAssertFalse(try ConfigLoader().parse("[window]\nheight = 0").window.isFixed, "either side at 0 is enough")
        XCTAssertFalse(try ConfigLoader().parse("[window]\nwidth = -1").window.isFixed, "negative is treated like 0")
    }
}
