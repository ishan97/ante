import XCTest
@testable import AnteCore

final class ConfigLoaderTests: XCTestCase {
    func testEmptyDocumentYieldsDefaults() throws {
        let config = try ConfigLoader().parse("")
        XCTAssertEqual(config, .default)
    }

    func testDefaultsMatchSpec() {
        let d = AnteConfig.default
        XCTAssertEqual(d.font.family, "Monaco")
        XCTAssertEqual(d.font.size, 12)
        XCTAssertTrue(d.font.ligatures)
        XCTAssertEqual(d.theme.name, "ante-dark")
        XCTAssertEqual(d.theme.appearance, .system)
        XCTAssertEqual(d.wallpaper.path, "")
        XCTAssertEqual(d.wallpaper.opacity, 0.35, accuracy: 0.0001)
        XCTAssertEqual(d.wallpaper.blur, 12, accuracy: 0.0001)
        XCTAssertTrue(d.hotkey.hideOnFocusLoss)
        XCTAssertEqual(d.shell.program, "")
        XCTAssertEqual(d.shell.arguments, ["-l"])
    }

    func testPartialOverrideKeepsOtherDefaults() throws {
        let toml = """
        [font]
        size = 15

        [theme]
        appearance = "dark"
        accent = "6ea8ff"
        background = "#101418"
        opacity = 0.05
        blur = false
        header = "eceef2"

        [hotkey]
        hide_on_focus_loss = false
        animation = "slide_left"
        width = 0.5
        height = 2
        """
        let config = try ConfigLoader().parse(toml)
        XCTAssertEqual(config.font.size, 15)
        XCTAssertEqual(config.font.family, "Monaco", "family not set: the default stays")
        XCTAssertEqual(config.theme.appearance, .dark)
        XCTAssertEqual(config.theme.name, "ante-dark")
        XCTAssertEqual(config.theme.accent, "#6EA8FF", "accent is normalised to #RRGGBB")
        XCTAssertNil(AnteConfig.default.theme.accent)
        XCTAssertThrowsError(try ConfigLoader().parse("[theme]\naccent = \"blue\""))
        XCTAssertEqual(HexColor.parse("#F5C46B"), HexColor(red: 245/255, green: 196/255, blue: 107/255))
        XCTAssertEqual(HexColor.parse("#F5C46B")?.hex, "#F5C46B")
        XCTAssertNil(HexColor.parse("#F5C4"))
        XCTAssertEqual(config.theme.background, "#101418")
        XCTAssertEqual(config.theme.opacity, 0.05)
        XCTAssertEqual(try ConfigLoader().parse("[theme]\nopacity = 0").theme.opacity, 0.01, "never fully invisible")
        XCTAssertEqual(config.theme.blur, 0, "blur = false still means none")
        XCTAssertEqual(config.theme.header, "#ECEEF2")
        XCTAssertNil(AnteConfig.default.theme.header)
        XCTAssertEqual(AnteConfig.default.theme.blur, 1)
        XCTAssertEqual(try ConfigLoader().parse("[theme]\nblur = 0.35").theme.blur, 0.35)
        XCTAssertEqual(try ConfigLoader().parse("[theme]\nblur = true").theme.blur, 1)
        XCTAssertEqual(try ConfigLoader().parse("[theme]\nblur = 7").theme.blur, 1, "clamped")
        XCTAssertNil(try ConfigLoader().parse("[theme]\nbackground = \"\"").theme.background, "empty means the theme's own")
        XCTAssertThrowsError(try ConfigLoader().parse("[theme]\nbackground = \"night\""))
        XCTAssertEqual(HexColor.parse("#000000")?.luminance, 0)
        XCTAssertEqual(HexColor(red: 0.5, green: 0.5, blue: 0.5).shaded(1.2).hex, "#999999")
        XCTAssertFalse(config.hotkey.hideOnFocusLoss)
        XCTAssertEqual(config.hotkey.animation, .slideLeft)
        XCTAssertEqual(AnteConfig.default.hotkey.animation, .slideDown)
        XCTAssertEqual(config.hotkey.width, 0.5)
        XCTAssertEqual(config.hotkey.height, 1, "clamped to the screen")
        XCTAssertEqual(AnteConfig.default.hotkey.width, 0.9)
        XCTAssertEqual(AnteConfig.default.hotkey.height, 0.6)
        XCTAssertThrowsError(try ConfigLoader().parse("[hotkey]\nanimation = \"wobble\""))
        XCTAssertEqual(config.shell.arguments, ["-l"])
    }

    func testIntegerAndFloatNumbersBothDecode() throws {
        XCTAssertEqual(try ConfigLoader().parse("[font]\nsize = 15").font.size, 15)
        XCTAssertEqual(try ConfigLoader().parse("[font]\nsize = 15.5").font.size, 15.5)
        XCTAssertEqual(try ConfigLoader().parse("[wallpaper]\nblur = 8\nopacity = 0.5").wallpaper.blur, 8)
    }

    func testUnknownKeysAreIgnored() throws {
        let toml = """
        future_top_level = 1
        [font]
        family = "Menlo"
        weight = "bold"
        """
        let config = try ConfigLoader().parse(toml)
        XCTAssertEqual(config.font.family, "Menlo")
    }

    func testSyntaxErrorReportsLine() {
        let toml = """
        [font]
        size = 13
        family = "unterminated
        """
        XCTAssertThrowsError(try ConfigLoader().parse(toml)) { error in
            guard let e = error as? ConfigError else { return XCTFail("wrong error type: \(error)") }
            XCTAssertEqual(e.line, 3)
            XCTAssertFalse(e.message.isEmpty)
        }
    }

    func testWrongTypeIsAnErrorNotACrash() {
        let toml = """
        [font]
        size = "thirteen"
        """
        XCTAssertThrowsError(try ConfigLoader().parse(toml)) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }

    func testLoadFromMissingFileReturnsMissingWithDefaults() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ante-missing-\(UUID().uuidString).toml")
        guard case let .missing(config) = ConfigLoader().load(from: url) else { return XCTFail() }
        XCTAssertEqual(config, .default)
    }

    func testLoadFromBrokenFileReturnsFailedWithDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ante-broken-\(UUID().uuidString).toml")
        try Data("[font\nsize = 1".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case let .failed(config, error) = ConfigLoader().load(from: url) else { return XCTFail() }
        XCTAssertEqual(config, .default)
        XCTAssertEqual(error.line, 1)
    }

    func testAppearanceParsesAllValues() throws {
        for (raw, expected) in [("system", AnteConfig.Appearance.system), ("light", .light), ("dark", .dark)] {
            let config = try ConfigLoader().parse("[theme]\nappearance = \"\(raw)\"")
            XCTAssertEqual(config.theme.appearance, expected)
        }
    }
}
