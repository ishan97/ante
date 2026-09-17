// Packages/AnteCore/Tests/AnteCoreTests/AgentTitleTests.swift
import XCTest
@testable import AnteCore

final class AgentTitleTests: XCTestCase {
    func testClaudeTitlesCarryStateAndName() {
        XCTAssertEqual(AgentTitle.parse("✳ Pong"), AgentTitle(state: .idle, name: "Pong"))
        XCTAssertEqual(AgentTitle.parse("◐ Pong"), AgentTitle(state: .busy, name: "Pong"))
        XCTAssertEqual(AgentTitle.parse("◒ Fix the login bug"), AgentTitle(state: .busy, name: "Fix the login bug"))
        XCTAssertEqual(AgentTitle.parse("✳ Claude Code"), AgentTitle(state: .idle, name: nil), "the product name is not a session name")
        XCTAssertEqual(AgentTitle.parse("◑ Claude Code"), AgentTitle(state: .busy, name: nil))
    }

    func testTitlesAreSanitisedAndCapped() {
        XCTAssertEqual(AgentTitle.parse("✳ Fix\u{07} the \u{1b}bug")?.name, "Fix the bug", "control characters are dropped")
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(AgentTitle.parse("◐ " + long)?.name?.count, 80)
    }

    func testOtherTitlesAreIgnored() {
        XCTAssertNil(AgentTitle.parse(""))
        XCTAssertNil(AgentTitle.parse("~/projects/ante"))
        XCTAssertNil(AgentTitle.parse("vim main.swift"))
        XCTAssertNil(AgentTitle.parse("Pong ✳"))
    }
}
