// Packages/AnteUI/Sources/AnteUI/Runtime/KeyBinding+AppKit.swift
import AppKit
import AnteCore

extension KeyBinding {
    /// Virtual key codes for the named keys, so a binding can be matched against an NSEvent
    /// without going through the menu (the workspace panel handles ⌘↩ itself).
    static let namedKeyCodes: [String: UInt16] = [
        "return": 36, "tab": 48, "space": 49, "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// True when `event` is this binding: the same modifiers (⌘⇧⌥⌃ only; caps lock, fn and the
    /// keypad flag are ignored) and the same key, by key code for named keys and by character
    /// otherwise (either the layout's character or the unshifted one, so a Cyrillic layout's ⌘K
    /// still works). Auto-repeat never counts: holding ⌘↩ must not flap the window.
    public func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat else { return false }
        var mods = Set<Modifier>()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods.insert(.cmd) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.alt) }
        if flags.contains(.control) { mods.insert(.ctrl) }
        guard mods == modifiers else { return false }
        if let code = Self.namedKeyCodes[key] { return event.keyCode == code }
        return [event.charactersIgnoringModifiers, event.characters].contains { $0?.lowercased() == key }
    }
}
