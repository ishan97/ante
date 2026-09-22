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
