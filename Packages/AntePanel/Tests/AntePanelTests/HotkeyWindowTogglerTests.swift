// Packages/AntePanel/Tests/AntePanelTests/HotkeyWindowTogglerTests.swift
import XCTest
import AppKit
import KeyboardShortcuts
@testable import AntePanel

@MainActor
final class HotkeyWindowTogglerTests: XCTestCase {
    func testDefaultShortcutIsOptionBacktickAndKeepsItsStoredName() {
        let shortcut = KeyboardShortcuts.Name.showHideAnte.defaultShortcut
        XCTAssertEqual(shortcut?.key, .backtick)
        XCTAssertEqual(shortcut?.modifiers, [.option])
        XCTAssertEqual(KeyboardShortcuts.Name.showHideAnte.rawValue, "toggleScratchPanel", "a user's recorded shortcut survives the rename")
    }

    func testHidesOnlyWhenShowingWithTheKeyboard() {
        XCTAssertTrue(HotkeyWindowToggler.shouldHide(windowVisible: true, windowKey: true))
        XCTAssertFalse(HotkeyWindowToggler.shouldHide(windowVisible: true, windowKey: false), "showing but behind another app: bring it front")
        XCTAssertFalse(HotkeyWindowToggler.shouldHide(windowVisible: false, windowKey: false), "closed or hidden: summon")
    }

    func testOffscreenFramesSitJustOutsideTheEdgeTheyEnterFrom() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let target = NSRect(x: 100, y: 100, width: 600, height: 400)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .slideDown, screen: screen).minY, 800)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .slideUp, screen: screen).maxY, 0)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .slideLeft, screen: screen).maxX, 0)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .slideRight, screen: screen).minX, 1000)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .fade, screen: screen), target)
        XCTAssertEqual(HotkeyWindowToggler.offscreenFrame(for: target, reveal: .none, screen: screen), target)
    }

    func testOverlayFrameIsAFractionOfTheScreenDockedTop() {
        let visible = NSRect(x: 0, y: 25, width: 1000, height: 775)
        let frame = HotkeyWindowToggler.overlayFrame(in: visible, width: 0.9, height: 0.6)
        XCTAssertEqual(frame, NSRect(x: 50, y: 335, width: 900, height: 465))
        XCTAssertEqual(HotkeyWindowToggler.overlayFrame(in: visible, width: 5, height: 0.1), NSRect(x: 0, y: 25 + 775 - 233, width: 1000, height: 233), "clamped")
    }

    func testSummonedFlagFollowsShowAndHide() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        let toggler = HotkeyWindowToggler(window: panel, hideOnFocusLoss: true, reveal: .none)
        let own = panel.frame   // includes the title bar, unlike the content rect
        XCTAssertFalse(toggler.isSummoned)
        toggler.show()
        XCTAssertTrue(toggler.isSummoned)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.level, HotkeyWindowToggler.summonedLevel)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.floating.rawValue, "above other apps' floating windows")
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces), "summoned: on every Space")
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary), "summoned: floats over full-screen apps")
        XCTAssertNotEqual(panel.frame.size, own.size, "summoned: overlay size")
        toggler.hide()
        XCTAssertFalse(toggler.isSummoned)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.level, .normal)
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces), "hidden: everyday Space behaviour is back")
    }

    func testSummonReturnsToWhereItWasHiddenFrom() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                            styleMask: [.titled, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        let toggler = HotkeyWindowToggler(window: panel, hideOnFocusLoss: false, reveal: .none)
        toggler.show()
        let overlay = panel.frame
        // The user drags and resizes the summoned window, then hides it.
        let moved = NSRect(x: overlay.minX + 40, y: overlay.minY - 60, width: overlay.width - 100, height: overlay.height - 50)
        panel.setFrame(moved, display: false)
        toggler.hide()
        XCTAssertEqual(panel.frame, moved, "hidden: stays where it was")
        toggler.show()
        XCTAssertEqual(panel.frame, moved, "summoned again: right where it was hidden from")
        toggler.hide()
        toggler.overlayHeight = 0.4   // a new overlay size starts fresh
        toggler.show()
        XCTAssertNotEqual(panel.frame, moved)
        toggler.hide()
    }
}
