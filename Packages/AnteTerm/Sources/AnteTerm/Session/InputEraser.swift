// Packages/AnteTerm/Sources/AnteTerm/Session/InputEraser.swift
import Foundation
import AnteCore

/// The keystrokes that make ⌘⌫ erase everything typed at the prompt of whatever owns the pane,
/// without Esc (which would interrupt a running agent).
///
/// A terminal cannot edit a program's line itself, it can only type at it, so each program gets
/// editing keys it is known to understand. Everything here was probed in a pty (Claude Code
/// 2.1.316, Codex 0.156, zsh 5.9, bash 3.2):
/// - **Claude Code and Codex** keep a multi-line draft, and ⌃U only clears from the cursor to the
///   start of its line (Claude's ⌃L "clear input" only redraws in 2.1.x). So Ante repeats
///   ⌃K ⌃U ⌫ ⌦: clear the cursor's line, then pull in the line break on each side. Each round
///   removes up to two lines; extra rounds on an empty draft do nothing.
/// - **Shells**: ⌃E ⌃U (end of line, kill to start). zsh's vi mode keeps the text right of the cursor.
/// - **Anything else**, including agents not probed yet and `claude -p` / `codex exec`, which read
///   no keys (typeahead would reach the shell afterwards): ⌃U alone, as ⌘⌫ sends in iTerm2.
public enum InputEraser {
    /// One draft round: ⌃K (kill to end of line), ⌃U (kill to start), ⌫ (join the line above), ⌦ (join the line below).
    static let draftRound: [UInt8] = [0x0B, 0x15, 0x7F, 0x1B, 0x5B, 0x33, 0x7E]
    /// Enough for a 64-line draft. A large paste is a single "[Pasted text]" chip, one ⌫.
    static let draftRounds = 32
    /// Claude Code mangles keys that arrive in one large read (12 rounds in one write left text
    /// behind; 8 did not), so the rounds go out in small writes, `chunkInterval` apart. Two
    /// chunks that land in the same read are still within what it handles. Probed while Claude
    /// was streaming a reply too: a 10-line draft still cleared completely.
    static let draftRoundsPerChunk = 4
    /// Seconds between chunks.
    public static let chunkInterval = 0.016

    static let ctrlU: [[UInt8]] = [[0x15]]

    /// The writes to send, in order, `chunkInterval` apart. `commandLine` is the foreground
    /// process's argv, to tell an interactive agent from a one-shot run of it.
    public static func chunks(for agent: AgentKind, commandLine: [String] = []) -> [[UInt8]] {
        switch agent {
        case .claude, .codex:
            guard isInteractive(commandLine) else { return ctrlU }
            let chunk = Array([[UInt8]](repeating: draftRound, count: draftRoundsPerChunk).joined())
            return Array(repeating: chunk, count: draftRounds / draftRoundsPerChunk)
        case .shell:
            return [[0x05, 0x15]]
        case .aider, .gemini, .goose, .amp, .opencode, .cursor, .pi, .command:
            return ctrlU
        }
    }

    /// Flags and subcommands that run Claude Code or Codex without its prompt.
    static let oneShotFlags: Set<String> = ["-p", "--print"]
    static let oneShotSubcommands: Set<String> = ["mcp", "mcp-server", "exec", "e", "doctor", "update"]

    /// False for `claude -p …`, `claude mcp serve`, `codex exec …` and the like. The subcommand is
    /// the first argument that is neither a flag nor a path (`node …/cli.js mcp` counts too).
    static func isInteractive(_ commandLine: [String]) -> Bool {
        let args = commandLine.dropFirst()
        if args.contains(where: oneShotFlags.contains) { return false }
        guard let first = args.first(where: { !$0.hasPrefix("-") && !$0.contains("/") }) else { return true }
        return !oneShotSubcommands.contains(first)
    }
}
