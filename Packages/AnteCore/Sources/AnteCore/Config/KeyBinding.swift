// Packages/AnteCore/Sources/AnteCore/Config/KeyBinding.swift
import Foundation

/// A keyboard shortcut in config form: `"cmd+shift+p"`, `"cmd+k"`, `"ctrl+alt+t"`.
/// Modifiers: cmd, shift, alt (or opt/option), ctrl (or control). Key: one character, or one of
/// up, down, left, right, return, escape, space, tab.
public struct KeyBinding: Equatable, Sendable, Codable {
    public enum Modifier: String, Sendable, CaseIterable, Comparable {
        case ctrl, alt, shift, cmd
        public static func < (a: Modifier, b: Modifier) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    public struct ParseError: Error, Equatable, Sendable {
        public let message: String
    }

    public let key: String
    public let modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public static let namedKeys: Set<String> = ["up", "down", "left", "right", "return", "escape", "space", "tab"]

    public static func parse(_ text: String) throws -> KeyBinding {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, !keyPart.isEmpty else { throw ParseError(message: "empty shortcut") }
        var modifiers = Set<Modifier>()
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.cmd)
            case "shift", "⇧": modifiers.insert(.shift)
            case "alt", "opt", "option", "⌥": modifiers.insert(.alt)
            case "ctrl", "control", "⌃": modifiers.insert(.ctrl)
            default: throw ParseError(message: "unknown modifier '\(part)'")
            }
        }
        guard keyPart.count == 1 || namedKeys.contains(keyPart) else {
            throw ParseError(message: "unknown key '\(keyPart)'")
        }
        guard !modifiers.isEmpty else { throw ParseError(message: "a shortcut needs at least one modifier") }
        return KeyBinding(key: keyPart, modifiers: modifiers)
    }

    /// Canonical config form: modifiers in ctrl, alt, shift, cmd order.
    public var text: String {
        (modifiers.sorted().map(\.rawValue) + [key]).joined(separator: "+")
    }

    /// Display form: ⌃⌥⇧⌘K.
    public var display: String {
        let symbols = modifiers.sorted().map { m -> String in
            switch m { case .ctrl: return "⌃"; case .alt: return "⌥"; case .shift: return "⇧"; case .cmd: return "⌘" }
        }.joined()
        let keyName: String
        switch key {
        case "up": keyName = "↑"; case "down": keyName = "↓"; case "left": keyName = "←"; case "right": keyName = "→"
        case "return": keyName = "⏎"; case "escape": keyName = "⎋"; case "space": keyName = "␣"; case "tab": keyName = "⇥"
        default: keyName = key.uppercased()
        }
        return symbols + keyName
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            self = try KeyBinding.parse(text)
        } catch let error as ParseError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

extension AnteConfig {
    /// Rebindable shortcuts. Anything not listed here is fixed.
    public struct Keys: Equatable, Sendable, Decodable {
        public var clearPane = KeyBinding(key: "k", modifiers: [.cmd])
        public var commandPalette = KeyBinding(key: "p", modifiers: [.cmd, .shift])
        public var find = KeyBinding(key: "f", modifiers: [.cmd])
        public var newSession = KeyBinding(key: "t", modifiers: [.cmd])
        public var closePane = KeyBinding(key: "w", modifiers: [.cmd])
        public var splitRight = KeyBinding(key: "d", modifiers: [.cmd])
        public var splitDown = KeyBinding(key: "d", modifiers: [.cmd, .shift])
        public var splitLeft = KeyBinding(key: "d", modifiers: [.cmd, .alt])
        public var splitUp = KeyBinding(key: "d", modifiers: [.cmd, .alt, .shift])
        public var toggleSidebar = KeyBinding(key: "s", modifiers: [.cmd, .alt])
        public var sessionsBoard = KeyBinding(key: "s", modifiers: [.cmd, .shift])
        public var insertFile = KeyBinding(key: "o", modifiers: [.cmd, .shift])
        public var scratchpad = KeyBinding(key: "t", modifiers: [.cmd, .shift])
        public var toggleFullscreen = KeyBinding(key: "return", modifiers: [.cmd])
        public var fontBigger = KeyBinding(key: "=", modifiers: [.cmd])
        public var fontSmaller = KeyBinding(key: "-", modifiers: [.cmd])
        public var fontReset = KeyBinding(key: "0", modifiers: [.cmd])

        public init() {}

        enum CodingKeys: String, CodingKey {
            case clearPane = "clear_pane", commandPalette = "command_palette", find, newSession = "new_session"
            case closePane = "close_pane", splitRight = "split_right", splitDown = "split_down"
            case splitLeft = "split_left", splitUp = "split_up", toggleSidebar = "toggle_sidebar"
            case sessionsBoard = "sessions_board", insertFile = "insert_file", scratchpad
            case toggleFullscreen = "toggle_fullscreen", fontBigger = "font_bigger", fontSmaller = "font_smaller", fontReset = "font_reset"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clearPane = try c.decodeIfPresent(KeyBinding.self, forKey: .clearPane) ?? clearPane
            commandPalette = try c.decodeIfPresent(KeyBinding.self, forKey: .commandPalette) ?? commandPalette
            find = try c.decodeIfPresent(KeyBinding.self, forKey: .find) ?? find
            newSession = try c.decodeIfPresent(KeyBinding.self, forKey: .newSession) ?? newSession
            closePane = try c.decodeIfPresent(KeyBinding.self, forKey: .closePane) ?? closePane
            splitRight = try c.decodeIfPresent(KeyBinding.self, forKey: .splitRight) ?? splitRight
            splitDown = try c.decodeIfPresent(KeyBinding.self, forKey: .splitDown) ?? splitDown
            splitLeft = try c.decodeIfPresent(KeyBinding.self, forKey: .splitLeft) ?? splitLeft
            splitUp = try c.decodeIfPresent(KeyBinding.self, forKey: .splitUp) ?? splitUp
            toggleSidebar = try c.decodeIfPresent(KeyBinding.self, forKey: .toggleSidebar) ?? toggleSidebar
            sessionsBoard = try c.decodeIfPresent(KeyBinding.self, forKey: .sessionsBoard) ?? sessionsBoard
            insertFile = try c.decodeIfPresent(KeyBinding.self, forKey: .insertFile) ?? insertFile
            scratchpad = try c.decodeIfPresent(KeyBinding.self, forKey: .scratchpad) ?? scratchpad
            toggleFullscreen = try c.decodeIfPresent(KeyBinding.self, forKey: .toggleFullscreen) ?? toggleFullscreen
            fontBigger = try c.decodeIfPresent(KeyBinding.self, forKey: .fontBigger) ?? fontBigger
            fontSmaller = try c.decodeIfPresent(KeyBinding.self, forKey: .fontSmaller) ?? fontSmaller
            fontReset = try c.decodeIfPresent(KeyBinding.self, forKey: .fontReset) ?? fontReset
        }

        /// (config key, label, binding) for every action, in Settings order.
        public var all: [(key: String, label: String, binding: KeyBinding)] {
            [("clear_pane", "Clear pane", clearPane), ("command_palette", "Command palette", commandPalette),
             ("find", "Find", find), ("new_session", "New session", newSession), ("close_pane", "Close pane", closePane),
             ("split_right", "Split right", splitRight), ("split_down", "Split down", splitDown),
             ("split_left", "Split left", splitLeft), ("split_up", "Split up", splitUp),
             ("toggle_sidebar", "Toggle sidebar", toggleSidebar), ("sessions_board", "Sessions", sessionsBoard),
             ("insert_file", "Insert file path…", insertFile), ("scratchpad", "To-do & notes", scratchpad),
             ("toggle_fullscreen", "Fill screen", toggleFullscreen), ("font_bigger", "Bigger text", fontBigger),
             ("font_smaller", "Smaller text", fontSmaller), ("font_reset", "Actual text size", fontReset)]
        }
    }
}

extension AnteConfig {
    public struct Cursor: Equatable, Sendable, Decodable {
        public enum Style: String, Sendable, Decodable, CaseIterable { case block, bar, underline }
        public var style: Style = .block
        /// Off by default: a blinking cursor is motion you never asked for.
        public var blink: Bool = false

        public init() {}

        private enum CodingKeys: String, CodingKey { case style, blink }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            style = try c.decodeIfPresent(Style.self, forKey: .style) ?? style
            blink = try c.decodeIfPresent(Bool.self, forKey: .blink) ?? blink
        }
    }
}
