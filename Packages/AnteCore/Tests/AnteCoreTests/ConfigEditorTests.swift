// Packages/AnteCore/Tests/AnteCoreTests/ConfigEditorTests.swift
import XCTest
@testable import AnteCore

final class ConfigEditorTests: XCTestCase {
    func testReplacesValueInExistingSectionKeepingCommentsAndOtherKeys() {
        let toml = """
        # Ante config
        [font]
        family = "JetBrains Mono"   # bundled
        size = 13
        ligatures = true

        [theme]
        name = "ante-dark"
        """
        let out = ConfigEditor.set(toml, section: "font", key: "size", value: .double(15))
        XCTAssertTrue(out.contains("# Ante config"))
        XCTAssertTrue(out.contains("size = 15\n"))
        XCTAssertTrue(out.contains("family = \"JetBrains Mono\"   # bundled"))
        XCTAssertTrue(out.contains("[theme]\nname = \"ante-dark\""))
        XCTAssertEqual(out.components(separatedBy: "size =").count, 2, "exactly one size key")
    }

    func testAppendsKeyToExistingSection() {
        let toml = "[font]\nsize = 13\n\n[theme]\nname = \"one-dark\"\n"
        let out = ConfigEditor.set(toml, section: "font", key: "ligatures", value: .bool(false))
        XCTAssertTrue(out.contains("[font]\nsize = 13\nligatures = false\n"), out)
        XCTAssertTrue(out.hasSuffix("[theme]\nname = \"one-dark\"\n"))
    }

    func testCreatesMissingSectionAtEnd() {
        let toml = "[font]\nsize = 13\n"
        let out = ConfigEditor.set(toml, section: "hotkey", key: "hide_on_focus_loss", value: .bool(false))
        XCTAssertEqual(out, "[font]\nsize = 13\n\n[hotkey]\nhide_on_focus_loss = false\n")
    }

    func testEmptyDocument() {
        let out = ConfigEditor.set("", section: "theme", key: "name", value: .string("gruvbox-dark"))
        XCTAssertEqual(out, "[theme]\nname = \"gruvbox-dark\"\n")
    }

    func testStringsAreEscaped() {
        let out = ConfigEditor.set("", section: "wallpaper", key: "path", value: .string("~/Pictures/a \"b\"\\c.jpg"))
        XCTAssertTrue(out.contains(#"path = "~/Pictures/a \"b\"\\c.jpg""#), out)
        XCTAssertEqual(try ConfigLoader().parse(out).wallpaper.path, "~/Pictures/a \"b\"\\c.jpg")
    }

    func testArraysAndIntegers() {
        var out = ConfigEditor.set("", section: "shell", key: "args", value: .stringArray(["-l", "-i"]))
        out = ConfigEditor.set(out, section: "font", key: "size", value: .int(12))
        XCTAssertTrue(out.contains("args = [\"-l\", \"-i\"]"))
        XCTAssertTrue(out.contains("size = 12"))
        XCTAssertEqual(try ConfigLoader().parse(out).shell.arguments, ["-l", "-i"])
    }

    func testDoesNotTouchSameKeyInOtherSection() {
        let toml = "[wallpaper]\npath = \"x\"\n[theme]\nname = \"a\"\n"
        let out = ConfigEditor.set(toml, section: "theme", key: "path", value: .string("y"))
        XCTAssertTrue(out.contains("[wallpaper]\npath = \"x\""))
        XCTAssertTrue(out.contains("[theme]\nname = \"a\"\npath = \"y\""))
    }

    func testWriteValidatesBeforeSaving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-ce-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        let editor = ConfigEditor(paths: paths)
        try editor.write(section: "font", key: "size", value: .double(14))
        XCTAssertEqual(ConfigLoader().load(from: paths.configFile).config.font.size, 14)
        // A value that breaks parsing must be refused and leave the file alone.
        XCTAssertThrowsError(try editor.write(section: "font", key: "size", value: .string("x\ny")))
        XCTAssertEqual(ConfigLoader().load(from: paths.configFile).config.font.size, 14)
    }

    func testNewDefaults() {
        let d = AnteConfig.default
        XCTAssertTrue(d.shell.integration)
        XCTAssertTrue(d.security.confirmMultilinePaste)
        let parsed = try? ConfigLoader().parse("[shell]\nintegration = false\n[security]\nconfirm_multiline_paste = false\n[scrollback]\npersist = false   # retired key, still tolerated")
        XCTAssertEqual(parsed?.shell.integration, false)
        XCTAssertEqual(parsed?.security.confirmMultilinePaste, false)
        XCTAssertNotNil(parsed, "a retired [scrollback] table does not break the config")
    }
}
