// Packages/AnteUI/Tests/AnteUITests/KeyBindingShortcutTests.swift
import XCTest
import SwiftUI
import AnteCore
@testable import AnteUI

final class KeyBindingShortcutTests: XCTestCase {
    func testNamedAndCharacterKeysMapToSwiftUIEquivalents() throws {
        XCTAssertEqual(try KeyBinding.parse("cmd+return").shortcut, KeyboardShortcut(.return, modifiers: .command))
        XCTAssertEqual(try KeyBinding.parse("cmd+=").shortcut, KeyboardShortcut("=", modifiers: .command))
        XCTAssertEqual(try KeyBinding.parse("cmd+-").shortcut, KeyboardShortcut("-", modifiers: .command))
        XCTAssertEqual(try KeyBinding.parse("cmd+0").shortcut, KeyboardShortcut("0", modifiers: .command))
        XCTAssertEqual(try KeyBinding.parse("ctrl+alt+up").shortcut, KeyboardShortcut(.upArrow, modifiers: [.control, .option]))
    }
}

extension KeyBindingShortcutTests {
    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testBindingsMatchRealKeyEvents() throws {
        let fullScreen = try KeyBinding.parse("cmd+return")
        XCTAssertTrue(fullScreen.matches(key(36, "\r", [.command])))
        XCTAssertTrue(fullScreen.matches(key(36, "\r", [.command, .capsLock])), "caps lock is not a modifier")
        XCTAssertFalse(fullScreen.matches(key(36, "\r", [])), "plain Return goes to the terminal")
        XCTAssertFalse(fullScreen.matches(key(36, "\r", [.command, .shift])))
        XCTAssertFalse(fullScreen.matches(key(76, "\u{3}", [.command])), "keypad Enter is a different key")
        let bigger = try KeyBinding.parse("cmd+=")
        XCTAssertTrue(bigger.matches(key(24, "=", [.command])))
        XCTAssertFalse(bigger.matches(key(24, "=", [.command, .option])))
        let up = try KeyBinding.parse("ctrl+alt+up")
        XCTAssertTrue(up.matches(key(126, "\u{F700}", [.control, .option])))
    }
}
