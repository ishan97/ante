import XCTest
import AppKit
@testable import AnteTerm

/// Only keys that put text on the line count as typing; a pending resume command is still typed
/// after Return, Esc or an arrow.
final class TypingKeyTests: XCTestCase {
    private func key(_ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
    }

    func testPrintableKeysAreTyping() {
        XCTAssertTrue(AnteTerminalView.isTyping(key("a")))
        XCTAssertTrue(AnteTerminalView.isTyping(key("A", .shift)))
        XCTAssertTrue(AnteTerminalView.isTyping(key(" ")))
        XCTAssertTrue(AnteTerminalView.isTyping(key("é", .option)))
    }

    func testControlAndNavigationKeysAreNot() {
        XCTAssertFalse(AnteTerminalView.isTyping(key("\r")))
        XCTAssertFalse(AnteTerminalView.isTyping(key("\u{1B}")))
        XCTAssertFalse(AnteTerminalView.isTyping(key("\t")))
        XCTAssertFalse(AnteTerminalView.isTyping(key("\u{7F}")))
        XCTAssertFalse(AnteTerminalView.isTyping(key(String(UnicodeScalar(NSUpArrowFunctionKey)!))))
        XCTAssertFalse(AnteTerminalView.isTyping(key("c", .control)))
        XCTAssertFalse(AnteTerminalView.isTyping(key("")))
    }
}
