// Packages/AnteTheme/Tests/AnteThemeTests/ImporterTests.swift
import XCTest
@testable import AnteTheme

final class ImporterTests: XCTestCase {
    private func itermPlist(_ entries: [String: (Double, Double, Double)]) -> Data {
        var dict: [String: Any] = [:]
        for (key, rgb) in entries {
            dict[key] = ["Red Component": rgb.0, "Green Component": rgb.1, "Blue Component": rgb.2, "Color Space": "sRGB"]
        }
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testITermColorsImport() throws {
        var entries: [String: (Double, Double, Double)] = [
            "Foreground Color": (1, 1, 1), "Background Color": (0, 0, 0), "Cursor Color": (1, 0, 0),
            "Selection Color": (0.2, 0.2, 0.2), "Selected Text Color": (0.9, 0.9, 0.9),
        ]
        for i in 0..<16 { entries["Ansi \(i) Color"] = (Double(i) / 15.0, 0, 0) }
        let theme = try ITermColorsImporter.import(plistData: itermPlist(entries), name: "Imported")
        XCTAssertEqual(theme.name, "Imported")
        XCTAssertEqual(theme.foreground, ThemeColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(theme.cursor, ThemeColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(theme.ansi[15], ThemeColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(theme.ansi[0], ThemeColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(theme.appearance, .dark, "dark background ⇒ dark theme")
    }

    func testITermColorsMissingAnsiEntryThrows() {
        let data = itermPlist(["Foreground Color": (1, 1, 1), "Background Color": (0, 0, 0)])
        XCTAssertThrowsError(try ITermColorsImporter.import(plistData: data, name: "x"))
    }

    func testITermColorsFillsOptionalFieldsFromDefaults() throws {
        var entries: [String: (Double, Double, Double)] = ["Foreground Color": (0, 0, 0), "Background Color": (1, 1, 1)]
        for i in 0..<16 { entries["Ansi \(i) Color"] = (0.5, 0.5, 0.5) }
        let theme = try ITermColorsImporter.import(plistData: itermPlist(entries), name: "light")
        XCTAssertEqual(theme.appearance, .light)
        XCTAssertEqual(theme.cursor, theme.foreground, "cursor defaults to foreground")
    }

    func testAlacrittyImport() throws {
        let toml = """
        [colors.primary]
        background = "#1d1f21"
        foreground = "0xc5c8c6"

        [colors.cursor]
        cursor = "#ffcc00"

        [colors.selection]
        background = "#373b41"
        text = "#ffffff"

        [colors.normal]
        black = "#1d1f21"
        red = "#cc6666"
        green = "#b5bd68"
        yellow = "#f0c674"
        blue = "#81a2be"
        magenta = "#b294bb"
        cyan = "#8abeb7"
        white = "#c5c8c6"

        [colors.bright]
        black = "#666666"
        red = "#d54e53"
        green = "#b9ca4a"
        yellow = "#e7c547"
        blue = "#7aa6da"
        magenta = "#c397d8"
        cyan = "#70c0b1"
        white = "#eaeaea"
        """
        let theme = try AlacrittyImporter.import(toml: toml, name: "Tomorrow Night")
        XCTAssertEqual(theme.background, ThemeColor(hex: "#1d1f21"))
        XCTAssertEqual(theme.foreground, ThemeColor(hex: "#c5c8c6"))
        XCTAssertEqual(theme.cursor, ThemeColor(hex: "#ffcc00"))
        XCTAssertEqual(theme.ansi[1], ThemeColor(hex: "#cc6666"))
        XCTAssertEqual(theme.ansi[9], ThemeColor(hex: "#d54e53"))
        XCTAssertEqual(theme.ansi.count, 16)
    }

    func testAlacrittyMissingBrightFallsBackToNormal() throws {
        let toml = """
        [colors.primary]
        background = "#000000"
        foreground = "#ffffff"
        [colors.normal]
        black = "#000000"
        red = "#ff0000"
        green = "#00ff00"
        yellow = "#ffff00"
        blue = "#0000ff"
        magenta = "#ff00ff"
        cyan = "#00ffff"
        white = "#ffffff"
        """
        let theme = try AlacrittyImporter.import(toml: toml, name: "min")
        XCTAssertEqual(theme.ansi[9], theme.ansi[1])
        XCTAssertEqual(theme.cursor, theme.foreground)
    }
}
