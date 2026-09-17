// Packages/AnteTheme/Sources/AnteTheme/Importers/ITermColorsImporter.swift
import Foundation

/// Reads iTerm2 `.itermcolors` files (a plist of `"Ansi N Color"` / `"Foreground Color"` dictionaries
/// with 0…1 `Red/Green/Blue Component` values).
public enum ITermColorsImporter {
    public struct ImportError: Error, Equatable, Sendable {
        public let message: String
    }

    public static func `import`(plistData: Data, name: String) throws -> TerminalTheme {
        guard let root = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw ImportError(message: "not a property list")
        }
        func color(_ key: String) -> ThemeColor? {
            guard let dict = root[key] as? [String: Any],
                  let r = dict["Red Component"] as? Double,
                  let g = dict["Green Component"] as? Double,
                  let b = dict["Blue Component"] as? Double else { return nil }
            func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            return ThemeColor(red: byte(r), green: byte(g), blue: byte(b))
        }
        guard let foreground = color("Foreground Color"), let background = color("Background Color") else {
            throw ImportError(message: "missing Foreground Color / Background Color")
        }
        var ansi: [ThemeColor] = []
        for index in 0..<16 {
            guard let c = color("Ansi \(index) Color") else {
                throw ImportError(message: "missing Ansi \(index) Color")
            }
            ansi.append(c)
        }
        return TerminalTheme(
            name: name,
            appearance: background.luminance < 0.5 ? .dark : .light,
            foreground: foreground,
            background: background,
            cursor: color("Cursor Color") ?? foreground,
            selectionBackground: color("Selection Color") ?? ansi[8],
            selectionForeground: color("Selected Text Color") ?? foreground,
            ansi: ansi
        )
    }
}
