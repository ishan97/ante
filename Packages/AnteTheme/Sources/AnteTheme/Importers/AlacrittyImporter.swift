// Packages/AnteTheme/Sources/AnteTheme/Importers/AlacrittyImporter.swift
import Foundation
import TOMLKit

/// Reads Alacritty's TOML colour scheme (`[colors.primary]`, `[colors.normal]`, `[colors.bright]`, …).
/// Alacritty's older YAML format is not supported; Alacritty itself migrated to TOML in 0.13.
public enum AlacrittyImporter {
    public struct ImportError: Error, Equatable, Sendable {
        public let message: String
    }

    private struct File: Decodable {
        struct Colors: Decodable {
            struct Primary: Decodable { var background: ThemeColor; var foreground: ThemeColor }
            struct Cursor: Decodable { var cursor: ThemeColor? }
            struct Selection: Decodable { var background: ThemeColor?; var text: ThemeColor? }
            struct Palette: Decodable {
                var black: ThemeColor; var red: ThemeColor; var green: ThemeColor; var yellow: ThemeColor
                var blue: ThemeColor; var magenta: ThemeColor; var cyan: ThemeColor; var white: ThemeColor
                var list: [ThemeColor] { [black, red, green, yellow, blue, magenta, cyan, white] }
            }
            var primary: Primary
            var cursor: Cursor?
            var selection: Selection?
            var normal: Palette
            var bright: Palette?
        }
        var colors: Colors
    }

    public static func `import`(toml: String, name: String) throws -> TerminalTheme {
        let file: File
        do {
            file = try TOMLDecoder().decode(File.self, from: toml)
        } catch {
            throw ImportError(message: String(describing: error))
        }
        let c = file.colors
        let normal = c.normal.list
        let bright = c.bright?.list ?? normal
        return TerminalTheme(
            name: name,
            appearance: c.primary.background.luminance < 0.5 ? .dark : .light,
            foreground: c.primary.foreground,
            background: c.primary.background,
            cursor: c.cursor?.cursor ?? c.primary.foreground,
            selectionBackground: c.selection?.background ?? bright[0],
            selectionForeground: c.selection?.text ?? c.primary.foreground,
            ansi: normal + bright
        )
    }
}
