// Packages/AnteTerm/Sources/AnteTerm/View/TerminalAppearance.swift
import AppKit
import SwiftTerm
import AnteTheme

/// Everything visual a terminal view needs, applied in one call so views never drift apart.
public struct TerminalAppearance {
    public var theme: TerminalTheme
    public var font: NSFont
    public var cursorStyle: CursorStyle

    public init(theme: TerminalTheme, font: NSFont, cursorStyle: CursorStyle) {
        self.theme = theme
        self.font = font
        self.cursorStyle = cursorStyle
    }

    @MainActor
    public func apply(to view: TerminalView) {
        let opacity = view.backgroundOpacity
        view.installColors(theme.ansi.map { Self.terminalColor($0) })
        view.nativeForegroundColor = Self.nsColor(theme.foreground)
        view.nativeBackgroundColor = Self.nsColor(theme.background)
        view.backgroundOpacity = opacity
        view.caretColor = Self.nsColor(theme.cursor)
        view.selectedTextBackgroundColor = Self.nsColor(theme.selectionBackground)
        view.selectedTextForegroundColor = Self.nsColor(theme.selectionForeground)
        if view.font != font {
            view.font = font
        }
        view.getTerminal().setCursorStyle(cursorStyle)
    }

    static func nsColor(_ c: ThemeColor) -> NSColor {
        NSColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
    }

    static func terminalColor(_ c: ThemeColor) -> SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(c.red) * 257, green: UInt16(c.green) * 257, blue: UInt16(c.blue) * 257)
    }
}

public enum SessionActivity: Equatable, Sendable {
    case idle
    case commandRunning
}
