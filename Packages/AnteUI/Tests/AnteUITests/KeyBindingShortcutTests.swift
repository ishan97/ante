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
    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags, unshifted: String? = nil, repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: unshifted ?? chars, isARepeat: repeating, keyCode: code)!
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
        XCTAssertTrue(up.matches(key(126, "\u{F700}", [.control, .option, .numericPad, .function])), "arrow keys carry the keypad and fn flags")
        XCTAssertTrue(fullScreen.matches(key(36, "\r", [.command, .function])), "fn is not a modifier")
        XCTAssertFalse(fullScreen.matches(key(36, "\r", [.command], repeating: true)), "auto-repeat never toggles")
        let clear = try KeyBinding.parse("cmd+k")
        XCTAssertTrue(clear.matches(key(40, "k", [.command], unshifted: "л")), "a non-Latin layout still reports the Latin character")
        XCTAssertFalse(bigger.matches(key(24, "+", [.command, .shift], unshifted: "=")), "shift makes it a different chord")
    }
}
