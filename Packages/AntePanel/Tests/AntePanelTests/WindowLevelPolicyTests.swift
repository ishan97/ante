// Packages/AntePanel/Tests/AntePanelTests/WindowLevelPolicyTests.swift
import XCTest
import AppKit
@testable import AntePanel

@MainActor
final class WindowLevelPolicyTests: XCTestCase {
    private func window(level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        w.level = level
        return w
    }

    func testLiftsANormalWindowAndRestoresItToNormal() {
        var policy = WindowLevelPolicy()
        let settings = window(level: .normal)
        let raised = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 2)
        XCTAssertEqual(policy.lift(settings, over: raised), raised)
        settings.level = raised
        XCTAssertNil(policy.lift(settings, over: raised), "already lifted: nothing to do")
        XCTAssertEqual(policy.restore(settings), .normal)
        XCTAssertNil(policy.restore(settings), "restored once; a second close is not ours")
    }

    func testAFloatingPanelKeepsFloatingAndIsNeverDemoted() {
        var policy = WindowLevelPolicy()
        let colours = window(level: .floating)
        let raised = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 2)
        XCTAssertEqual(policy.lift(colours, over: raised), raised)
        XCTAssertEqual(policy.restore(colours), .floating, "back to floating, not normal")
        XCTAssertNil(policy.lift(colours, over: .normal), "nothing to lift over an ordinary panel")
        XCTAssertNil(policy.restore(colours), "and so nothing to restore")
    }
}
