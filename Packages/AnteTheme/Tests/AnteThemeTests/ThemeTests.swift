// Packages/AnteTheme/Tests/AnteThemeTests/ThemeTests.swift
import XCTest
@testable import AnteTheme

final class ThemeTests: XCTestCase {
    func testHexParsing() {
        XCTAssertEqual(ThemeColor(hex: "#FF8000"), ThemeColor(red: 255, green: 128, blue: 0))
        XCTAssertEqual(ThemeColor(hex: "ff8000"), ThemeColor(red: 255, green: 128, blue: 0))
        XCTAssertEqual(ThemeColor(hex: "0xff8000"), ThemeColor(red: 255, green: 128, blue: 0))
        XCTAssertNil(ThemeColor(hex: "#12345"))
        XCTAssertNil(ThemeColor(hex: "#GGGGGG"))
        XCTAssertEqual(ThemeColor(red: 255, green: 128, blue: 0).hex, "#FF8000")
    }

    func testAllBuiltInsLoadAndAreComplete() throws {
        let loader = ThemeLoader(userDirectory: nil)
        XCTAssertEqual(Set(loader.builtInNames),
                       ["ante-dark", "ante-light", "one-dark", "solarized-dark", "gruvbox-dark", "catppuccin-mocha"])
        for name in loader.builtInNames {
            let theme = try XCTUnwrap(loader.theme(named: name), name)
            XCTAssertEqual(theme.ansi.count, 16, name)
            XCTAssertFalse(theme.name.isEmpty)
        }
    }

    func testAnteVariantResolvesByAppearance() {
        let loader = ThemeLoader(userDirectory: nil)
        XCTAssertEqual(loader.resolve(name: "ante", preferDark: true).name, "Ante Dark")
        XCTAssertEqual(loader.resolve(name: "ante", preferDark: false).name, "Ante Light")
        XCTAssertEqual(loader.resolve(name: "one-dark", preferDark: false).name, "One Dark", "explicit names apply as-is")
        XCTAssertEqual(loader.resolve(name: "does-not-exist", preferDark: true).name, "Ante Dark", "unknown falls back to Ante")
    }

    func testUserThemeOverridesBuiltInAndBadFilesAreSkipped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ante-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = TerminalTheme(name: "Mine", appearance: .dark,
                                   foreground: ThemeColor(hex: "#ffffff")!, background: ThemeColor(hex: "#000000")!,
                                   cursor: ThemeColor(hex: "#ff0000")!,
                                   selectionBackground: ThemeColor(hex: "#333333")!, selectionForeground: ThemeColor(hex: "#ffffff")!,
                                   ansi: (0..<16).map { ThemeColor(red: UInt8($0 * 16), green: 0, blue: 0) })
        try Data(custom.toml.utf8).write(to: dir.appendingPathComponent("one-dark.toml"))
        try Data("not = [toml".utf8).write(to: dir.appendingPathComponent("broken.toml"))
        let loader = ThemeLoader(userDirectory: dir)
        XCTAssertEqual(loader.theme(named: "one-dark")?.name, "Mine")
        XCTAssertNil(loader.theme(named: "broken"))
        XCTAssertTrue(loader.availableNames.contains("one-dark"))
    }

    func testTomlRoundTrip() throws {
        let loader = ThemeLoader(userDirectory: nil)
        let original = try XCTUnwrap(loader.theme(named: "gruvbox-dark"))
        let reparsed = try TerminalTheme.parse(toml: original.toml)
        XCTAssertEqual(reparsed, original)
    }

    func testMissingAnsiEntriesIsAnError() {
        let toml = """
        name = "Short"
        [colors]
        foreground = "#ffffff"
        background = "#000000"
        ansi = ["#000000", "#ffffff"]
        """
        XCTAssertThrowsError(try TerminalTheme.parse(toml: toml))
    }
}
