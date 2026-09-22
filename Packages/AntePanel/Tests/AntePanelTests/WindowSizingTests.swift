// Packages/AntePanel/Tests/AntePanelTests/WindowSizingTests.swift
import XCTest
@testable import AntePanel

final class WindowSizingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1512, height: 857)   // a 16-inch laptop display minus the menu bar
    private let minSize = CGSize(width: 720, height: 420)

    func testFractionOfTheScreenAnchoredTopLeft() {
        let f = WindowSizing.frame(fraction: 0.5, 0.5, in: screen, minSize: minSize)
        XCTAssertEqual(f.size, CGSize(width: 756, height: 429))
        XCTAssertEqual(f.minX, screen.minX)
        XCTAssertEqual(f.maxY, screen.maxY, "flush with the menu bar")
    }

    func testSecondDisplayKeepsItsOwnOrigin() {
        let external = CGRect(x: -223, y: 982, width: 1920, height: 1050)
        let f = WindowSizing.frame(fraction: 1, 0.65, in: external, minSize: minSize)
        XCTAssertEqual(f, CGRect(x: -223, y: 982 + 1050 - 683, width: 1920, height: 683))
    }

    func testClampsBetweenTheMinimumAndTheScreen() {
        let small = WindowSizing.frame(fraction: 0.1, 0.1, in: screen, minSize: minSize)
        XCTAssertEqual(small.size, minSize)
        let huge = WindowSizing.frame(fraction: 3, 3, in: screen, minSize: minSize)
        XCTAssertEqual(huge.size, screen.size)
        XCTAssertEqual(huge.origin, screen.origin)
    }
}
