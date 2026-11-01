// Packages/AnteUI/Sources/AnteUI/Tips/TipCatalog.swift
import Foundation
import AnteCore

/// What Ante can do that people rarely find on their own, most useful first. Keys come from the
/// user's own bindings, so a rebound shortcut is never taught wrong.
public enum TipCatalog {
    /// `hotkey` is the global show/hide shortcut as displayed (nil when the user cleared it); the
    /// timer lengths are the user's own.
    public static func tips(keys: AnteConfig.Keys, hotkey: String?, focusMinutes: Int = 25, breakMinutes: Int = 5) -> [Tip] {
        var out: [Tip] = []
        if let hotkey, !hotkey.isEmpty {
            out.append(Tip(id: "hotkey", symbol: "keyboard", [
                .text("Press "), .key(hotkey), .text(" in any app to drop Ante over it, and again to hide it. Your terminal is always one key away."),
            ]))
        }
        out += [
            Tip(id: "fill-screen", symbol: "arrow.up.left.and.arrow.down.right", [
                .key(keys.toggleFullscreen.display), .text(" fills the whole screen; the menu bar and Dock slide away. Press it again to go back."),
            ]),
            Tip(id: "sessions-board", symbol: "rectangle.3.group", [
                .key(keys.sessionsBoard.display), .text(" shows every session sorted into Working, Waiting for you and Idle."),
            ]),
            Tip(id: "palette", symbol: "command", [
                .key(keys.commandPalette.display), .text(" opens the command palette: sessions, actions, themes and recent folders in one search."),
            ]),
            Tip(id: "splits", symbol: "rectangle.split.2x1", [
                .key(keys.splitRight.display), .text(" splits right, "), .key(keys.splitDown.display), .text(" splits down, and "),
                .key("⌘⌥←↑→↓"), .text(" moves between panes."),
            ]),
            Tip(id: "history", symbol: "clock.arrow.circlepath", [
                .text("Past Claude Code, Codex, OpenCode and Pi sessions are in History on the Sessions board. Click one to pick up where you left off."),
            ]),
            Tip(id: "restore-sessions", symbol: "arrow.clockwise", [
                .text("Want your sessions back after quitting? Settings → General → Reopen sessions brings back every session, split and agent conversation."),
            ]),
            Tip(id: "new-folder", symbol: "folder.badge.plus", [
                .text("Starting something new? The folder button at the bottom of the sidebar makes the folder, adds it as a project and opens a session in it."),
            ]),
            Tip(id: "waiting", symbol: "bell.badge", [
                .text("Ante tells you when an agent is waiting for you. Install the Claude Code hook in Settings → Agents for an exact signal."),
            ]),
            Tip(id: "insert-file", symbol: "doc.badge.plus", [
                .text("Drop files onto the terminal, or press "), .key(keys.insertFile.display), .text(", to type their paths."),
            ]),
            Tip(id: "commands", symbol: "arrow.up.arrow.down", [
                .key("⌘↑"), .text(" and "), .key("⌘↓"), .text(" jump between commands; "), .key("⌘⇧A"), .text(" selects the last command's output."),
            ]),
            Tip(id: "scratchpad", symbol: "checklist", [
                .key(keys.scratchpad.display), .text(" opens a to-do list and notes that stay with you across sessions."),
            ]),
            Tip(id: "tokens", symbol: "flame", [
                .text("The flame in the toolbar counts the tokens your agents used in the last 24 hours. Click it for 7 days, 30 days and up to a year."),
            ]),
            Tip(id: "jump-sessions", symbol: "number", [
                .key("⌘1"), .text("–"), .key("⌘9"), .text(" jump straight to a session; "), .key("⌘⇧["), .text(" and "), .key("⌘⇧]"), .text(" step through them."),
            ]),
            Tip(id: "open-links", symbol: "cursorarrow.click", [
                .key("⌘"), .text("-click a link or a file path to open it."),
            ]),
            Tip(id: "focus-timer", symbol: "timer", [
                .text("The timer in the toolbar runs focus blocks: \(focusMinutes) minutes on, \(breakMinutes) off, a longer break every fourth."),
            ]),
            Tip(id: "erase-input", symbol: "delete.left", [
                .key("⌘⌫"), .text(" erases everything you have typed, even a long Claude prompt, without Esc — a running agent keeps working."),
            ]),
            Tip(id: "find", symbol: "magnifyingglass", [
                .key(keys.find.display), .text(" searches the scrollback of the focused pane."),
            ]),
            Tip(id: "sidebar", symbol: "sidebar.left", [
                .key(keys.toggleSidebar.display), .text(" hides the sidebar when you want the room."),
            ]),
            Tip(id: "text-size", symbol: "textformat.size", [
                .key(keys.fontBigger.display), .text(" and "), .key(keys.fontSmaller.display), .text(" change the text size; "),
                .key(keys.fontReset.display), .text(" puts it back."),
            ]),
            Tip(id: "themes", symbol: "paintpalette", [
                .text("Bring your iTerm2 or Alacritty colours along: Settings → Appearance → Import Theme."),
            ]),
        ]
        return out
    }
}
