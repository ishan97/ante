// Packages/AnteCore/Sources/AnteCore/Agents/AgentTitle.swift
import Foundation

/// What an agent tells the terminal through its window title. Claude Code sets
/// `✳ <session name>` while it waits for input and rotates `◐ ◓ ◑ ◒ <session name>` while it
/// works, so the title is a real-time, hook-free signal of both the name and the state.
public struct AgentTitle: Equatable, Sendable {
    public enum State: Equatable, Sendable { case busy, idle }

    public let state: State
    /// The session name, or nil while the agent still shows its product name.
    public let name: String?

    public init(state: State, name: String?) {
        self.state = state
        self.name = name
    }

    static let idleGlyphs: Set<Character> = ["✳"]
    static let busyGlyphs: Set<Character> = ["◐", "◓", "◑", "◒"]
    static let productNames: Set<String> = ["Claude Code", "Claude"]
    /// Longer than any sidebar can show; keeps a runaway title from bloating state.json.
    static let maxNameLength = 80

    /// Returns nil for titles that are not an agent's (a shell's cwd, an editor's file name…).
    public static func parse(_ title: String) -> AgentTitle? {
        // A program may put anything in its title; control characters have no business in a label.
        let trimmed = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        let state: State
        if idleGlyphs.contains(first) { state = .idle }
        else if busyGlyphs.contains(first) { state = .busy }
        else { return nil }
        let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        let name = rest.isEmpty || productNames.contains(rest) ? nil : String(rest.prefix(maxNameLength))
        return AgentTitle(state: state, name: name)
    }
}
