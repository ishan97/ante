// Packages/AntePanel/Tests/AntePanelTests/WindowSizingTests.swift
import XCTest
@testable import AntePanel

final class WindowSizingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1512, height: 857)   // a 16-inch laptop display minus the menu bar
    private let minSize = CGSize(width: 720, height: 420)

    func testFractionOfTheScreenCentredWhenThereIsNoPreviousFrame() {
        let f = WindowSizing.frame(fraction: 0.5, 0.5, in: screen, previous: nil, minSize: minSize)
        XCTAssertEqual(f.size, CGSize(width: 756, height: 429))
        XCTAssertEqual(f.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(f.midY, screen.midY, accuracy: 1)
    }

    func testKeepsTheTopLeftCornerWhenTheNewSizeStillFitsThere() {
        let previous = CGRect(x: 100, y: 300, width: 900, height: 500)
        let f = WindowSizing.frame(fraction: 0.5, 0.5, in: screen, previous: previous, minSize: minSize)
        XCTAssertEqual(f.minX, 100)
        XCTAssertEqual(f.maxY, 800)
    }

    func testCentresInsteadWhenTheCornerWouldPushItOffScreen() {
        let previous = CGRect(x: 1200, y: 30, width: 300, height: 300)
        let f = WindowSizing.frame(fraction: 0.8, 0.8, in: screen, previous: previous, minSize: minSize)
        XCTAssertTrue(screen.contains(f))
        XCTAssertEqual(f.midX, screen.midX, accuracy: 1)
    }

    func testClampsBetweenTheMinimumAndTheScreen() {
        let small = WindowSizing.frame(fraction: 0.1, 0.1, in: screen, previous: nil, minSize: minSize)
        XCTAssertEqual(small.size, minSize)
        let huge = WindowSizing.frame(fraction: 3, 3, in: screen, previous: nil, minSize: minSize)
        XCTAssertEqual(huge.size, screen.size)
    }
}
