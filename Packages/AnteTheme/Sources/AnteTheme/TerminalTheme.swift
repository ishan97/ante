// Packages/AnteTheme/Sources/AnteTheme/TerminalTheme.swift
import Foundation
import TOMLKit

/// A terminal colour scheme: 16 ANSI colours plus the handful of UI colours a terminal needs.
public struct TerminalTheme: Hashable, Sendable {
    public enum Appearance: String, Sendable, Codable { case dark, light }

    public struct ParseError: Error, Equatable, Sendable {
        public let message: String
    }

    public var name: String
    public var appearance: Appearance
    public var foreground: ThemeColor
    public var background: ThemeColor
    public var cursor: ThemeColor
    public var selectionBackground: ThemeColor
    public var selectionForeground: ThemeColor
    /// Exactly 16 entries: 0–7 normal, 8–15 bright.
    public var ansi: [ThemeColor]

    public init(name: String, appearance: Appearance, foreground: ThemeColor, background: ThemeColor, cursor: ThemeColor,
                selectionBackground: ThemeColor, selectionForeground: ThemeColor, ansi: [ThemeColor]) {
        self.name = name
        self.appearance = appearance
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.ansi = ansi
    }

    // MARK: TOML

    private struct File: Decodable {
        struct Colors: Decodable {
            var foreground: ThemeColor
            var background: ThemeColor
            var cursor: ThemeColor?
            var selection_background: ThemeColor?
            var selection_foreground: ThemeColor?
            var ansi: [ThemeColor]
        }
        var name: String
        var appearance: Appearance?
        var colors: Colors
    }

    public static func parse(toml: String) throws -> TerminalTheme {
        let file: File
        do {
            file = try TOMLDecoder().decode(File.self, from: toml)
        } catch {
            throw ParseError(message: String(describing: error))
        }
        guard file.colors.ansi.count == 16 else {
            throw ParseError(message: "colors.ansi must have 16 entries, got \(file.colors.ansi.count)")
        }
        let c = file.colors
        return TerminalTheme(
            name: file.name,
            appearance: file.appearance ?? (c.background.luminance < 0.5 ? .dark : .light),
            foreground: c.foreground,
            background: c.background,
            cursor: c.cursor ?? c.foreground,
            selectionBackground: c.selection_background ?? c.ansi[8],
            selectionForeground: c.selection_foreground ?? c.foreground,
            ansi: c.ansi
        )
    }

    /// Serialises in the same shape `parse` reads, so importers can write files users can edit.
    public var toml: String {
        let ansiList = ansi.map { "\"\($0.hex)\"" }.joined(separator: ", ")
        return """
        name = "\(name.replacingOccurrences(of: "\"", with: "\\\""))"
        appearance = "\(appearance.rawValue)"

        [colors]
        foreground = "\(foreground.hex)"
        background = "\(background.hex)"
        cursor = "\(cursor.hex)"
        selection_background = "\(selectionBackground.hex)"
        selection_foreground = "\(selectionForeground.hex)"
        ansi = [\(ansiList)]

        """
    }
}
