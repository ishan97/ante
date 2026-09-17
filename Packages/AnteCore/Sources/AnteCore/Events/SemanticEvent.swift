import Foundation

/// What the shell told the terminal via OSC 133 (semantic prompt) and OSC 7 (working directory).
/// This is the whole vocabulary later features (run detection, gutter marks, cost tracking) build on.
public enum SemanticEvent: Equatable, Sendable {
    /// OSC 133;A — the shell is about to draw a prompt.
    case promptStarted
    /// OSC 133;C — the user's command is starting; output follows.
    case commandStarted
    /// OSC 133;D[;code] — the command finished. `nil` when the shell did not report a code.
    case commandFinished(exitCode: Int?)
    /// OSC 7 — the shell's working directory changed.
    case cwdChanged(URL)
    /// OSC 9 — the program posted a desktop notification (the escape several terminals honour), e.g. Claude Code's
    /// "Claude needs your permission". Progress reports (`9;4;…`) are not notifications.
    case notification(String)
}
