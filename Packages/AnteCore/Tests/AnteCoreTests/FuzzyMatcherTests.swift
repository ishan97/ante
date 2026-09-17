// Packages/AnteCore/Tests/AnteCoreTests/FuzzyMatcherTests.swift
import XCTest
@testable import AnteCore

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesEverythingEqually() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", in: "anything"), 0)
    }

    func testSubsequenceRequired() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "nss", in: "New Session"))
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", in: "New Session"))
        XCTAssertNil(FuzzyMatcher.score(query: "snn", in: "New Session"), "order matters")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(FuzzyMatcher.score(query: "NEW", in: "new session"), FuzzyMatcher.score(query: "new", in: "New Session"))
    }

    func testWordStartsAndPrefixesRankHigher() {
        let prefix = FuzzyMatcher.score(query: "spl", in: "Split Right")!
        let scattered = FuzzyMatcher.score(query: "spl", in: "Session: plans")!
        XCTAssertGreaterThan(prefix, scattered)
        let wordStarts = FuzzyMatcher.score(query: "sr", in: "Split Right")!
        let inside = FuzzyMatcher.score(query: "sr", in: "Search")!
        XCTAssertGreaterThan(wordStarts, inside)
    }

    func testRankOrdersByScoreThenStability() {
        let items = ["Toggle Sidebar", "Split Down", "Split Right", "Session 3"]
        XCTAssertEqual(FuzzyMatcher.rank(items, query: "spli", text: { $0 }), ["Split Down", "Split Right"])
        XCTAssertEqual(FuzzyMatcher.rank(items, query: "", text: { $0 }), items)
    }
}
