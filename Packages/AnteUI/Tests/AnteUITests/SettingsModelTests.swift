// Packages/AnteUI/Tests/AnteUITests/SettingsModelTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class SettingsModelTests: XCTestCase {
    func testSettersWriteConfigAndImportCreatesATheme() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: [], kind: .other)
        })
        let model = SettingsModel(runtime: runtime)
        model.fontSize = 17
        model.themeName = "one-dark"
        model.accentHex = "6ea8ff"
        XCTAssertEqual(model.accentHex, "#6EA8FF")
        model.backgroundHex = "#101418"
        model.windowOpacity = 0.876
        XCTAssertEqual(model.backgroundHex, "#101418")
        XCTAssertTrue(model.hasCustomBackground)
        XCTAssertEqual(model.fontSize, 17, "the new value shows before the coalesced write lands")
        model.flushPendingWrites()
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertTrue(text.contains("[font]\nsize = 17"))
        XCTAssertTrue(text.contains("name = \"one-dark\""))
        XCTAssertTrue(text.contains("accent = \"#6EA8FF\""), text)
        XCTAssertTrue(text.contains("background = \"#101418\""), text)
        XCTAssertTrue(text.contains("opacity = 0.88"), text)
        model.backgroundHex = nil
        XCTAssertFalse(model.hasCustomBackground, "clearing shows immediately")
        model.flushPendingWrites()
        XCTAssertNil(try ConfigLoader().load(from: paths.configFile).config.theme.background)
        XCTAssertNil(model.lastError)

        let itermFile = root.appendingPathComponent("My Colors.itermcolors")
        var dict: [String: Any] = [:]
        for (key, v) in [("Foreground Color", 1.0), ("Background Color", 0.0)] + (0..<16).map { ("Ansi \($0) Color", 0.5) } {
            dict[key] = ["Red Component": v, "Green Component": v, "Blue Component": v]
        }
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: itermFile)
        let slug = try model.importTheme(from: itermFile)
        XCTAssertEqual(slug, "my-colors")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.themesDirectory.appendingPathComponent("my-colors.toml").path))
        XCTAssertTrue(model.themeNames.contains("my-colors"))
        runtime.prepareForQuit()
    }
}

extension SettingsModelTests {
    func testAppearanceSwitchMovesAntesOwnThemeWithItAndShowsAtOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: [], kind: .other)
        })
        let model = SettingsModel(runtime: runtime)
        model.themeName = "ante-dark"
        model.backgroundHex = "#101418"
        model.appearance = .light
        XCTAssertEqual(model.appearance, .light, "the segmented control must not snap back before the write lands")
        XCTAssertEqual(model.themeName, "ante-light")
        XCTAssertFalse(model.hasCustomBackground, "a custom background would keep deciding light vs dark")
        model.flushPendingWrites()
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertTrue(text.contains("name = \"ante-light\""), text)
        XCTAssertTrue(text.contains("appearance = \"light\""), text)

        model.appearance = .system
        XCTAssertEqual(model.themeName, "ante", "System: the ante family follows the Mac")
        model.themeName = "gruvbox-dark"
        model.appearance = .light
        XCTAssertEqual(model.themeName, "gruvbox-dark", "third-party themes are left alone")
    }
}

extension SettingsModelTests {
    func testFontStepsStayInRangeAndWindowToggleWritesZeros() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: [], kind: .other)
        })
        let model = SettingsModel(runtime: runtime)
        model.stepFontSize(by: 1); model.stepFontSize(by: 1)
        XCTAssertEqual(model.fontSize, 14, "two steps up from the default 12")
        model.stepFontSize(by: -30)
        XCTAssertEqual(model.fontSize, 8, "clamped at the slider's floor")
        model.resetFontSize()
        XCTAssertEqual(model.fontSize, 12, "iTerm2's default size")

        XCTAssertTrue(model.windowSizeIsFixed)
        model.windowSizeIsFixed = false
        XCTAssertEqual(model.windowWidth, 0)
        model.windowSizeIsFixed = true
        XCTAssertEqual(model.windowHeight, 0.8)
        model.flushPendingWrites()
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        XCTAssertTrue(text.contains("[window]"), text)
        XCTAssertTrue(text.contains("width = 0.8"), text)
    }
}
