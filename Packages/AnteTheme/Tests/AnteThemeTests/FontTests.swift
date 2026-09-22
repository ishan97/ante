// Packages/AnteTheme/Tests/AnteThemeTests/FontTests.swift
import XCTest
import AppKit
@testable import AnteTheme

@MainActor
final class FontTests: XCTestCase {
    func testBundledJetBrainsMonoRegistersAndResolves() {
        FontRegistrar.registerBundledFonts()
        let font = FontResolver.resolve(family: "JetBrains Mono", size: 13)
        XCTAssertEqual(font.familyName, "JetBrains Mono")
        XCTAssertEqual(font.pointSize, 13)
        XCTAssertTrue(font.isFixedPitch)
    }

    func testUnknownFamilyFallsBackToAMonospaceFont() {
        let font = FontResolver.resolve(family: "Definitely Not A Font", size: 15)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertEqual(font.pointSize, 15)
    }

    func testResolvedFontCarriesSymbolFallbacks() {
        FontRegistrar.registerBundledFonts()
        let font = FontResolver.resolve(family: "JetBrains Mono", size: 13)
        let cascade = font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor] ?? []
        XCTAssertFalse(cascade.isEmpty, "at least Apple Symbols / Emoji should be attached")
        XCTAssertEqual(font.familyName, "JetBrains Mono", "the cascade must not change the main family")
        if FontResolver.symbolFallbackFamilies().contains(where: { $0.contains("Nerd Font") }) {
            let first = cascade.first?.object(forKey: .family) as? String
            XCTAssertTrue(first?.contains("Nerd Font") ?? false, "Nerd Fonts come first when installed: \(String(describing: first))")
        }
    }

    func testFallbackChainStartsWithTheDefaultThenTheBundledFont() {
        XCTAssertEqual(Array(FontResolver.fallbackChain.prefix(2)), ["Monaco", "JetBrains Mono"])
        XCTAssertTrue(FontResolver.fallbackChain.contains("Menlo"))
    }
}
