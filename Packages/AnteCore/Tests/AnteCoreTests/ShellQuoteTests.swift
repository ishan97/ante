// Packages/AnteCore/Tests/AnteCoreTests/ShellQuoteTests.swift
import XCTest
@testable import AnteCore

final class ShellQuoteTests: XCTestCase {
    func testSafePathsStayBare() {
        XCTAssertEqual(ShellQuote.quote("/Users/me/code/main.swift"), "/Users/me/code/main.swift")
        XCTAssertEqual(ShellQuote.quote("a-b_c.txt"), "a-b_c.txt")
    }

    func testUnsafePathsAreSingleQuoted() {
        XCTAssertEqual(ShellQuote.quote("/Users/me/My Docs/a.txt"), "'/Users/me/My Docs/a.txt'")
        XCTAssertEqual(ShellQuote.quote("it's.txt"), "'it'\\''s.txt'")
        XCTAssertEqual(ShellQuote.quote("$(rm -rf ~)"), "'$(rm -rf ~)'")
        XCTAssertEqual(ShellQuote.quote("-rf"), "'-rf'", "a leading dash would read as an option")
        XCTAssertEqual(ShellQuote.quote("~/x"), "'~/x'", "a literal tilde must not expand")
        XCTAssertEqual(ShellQuote.quote("=ls"), "'=ls'", "zsh expands a leading = to a PATH lookup")
        XCTAssertEqual(ShellQuote.quote(""), "''")
    }

    func testLineJoinsWithTrailingSpace() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b c/")]
        XCTAssertEqual(ShellQuote.line(for: urls), "/tmp/a.txt '/tmp/b c' ")
        XCTAssertEqual(ShellQuote.line(for: []), "")
    }
}
