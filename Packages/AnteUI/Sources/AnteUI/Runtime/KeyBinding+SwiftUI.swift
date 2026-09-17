// Packages/AnteUI/Sources/AnteUI/Runtime/KeyBinding+SwiftUI.swift
import SwiftUI
import AnteCore

extension KeyBinding {
    /// The SwiftUI shortcut for a menu item.
    public var shortcut: KeyboardShortcut {
        let equivalent: KeyEquivalent
        switch key {
        case "up": equivalent = .upArrow
        case "down": equivalent = .downArrow
        case "left": equivalent = .leftArrow
        case "right": equivalent = .rightArrow
        case "return": equivalent = .return
        case "escape": equivalent = .escape
        case "space": equivalent = .space
        case "tab": equivalent = .tab
        default: equivalent = KeyEquivalent(key.first ?? "k")
        }
        var mods: EventModifiers = []
        if modifiers.contains(.cmd) { mods.insert(.command) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        if modifiers.contains(.alt) { mods.insert(.option) }
        if modifiers.contains(.ctrl) { mods.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: mods)
    }
}
