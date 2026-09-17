// Packages/AnteTerm/Tests/AnteTermTests/AppearanceAndActivityTests.swift
import XCTest
import AppKit
import SwiftTerm
import AnteCore
import AnteTheme
@testable import AnteTerm

@MainActor
final class AppearanceAndActivityTests: XCTestCase {
    private func makeController(bus: RunEventBus = RunEventBus(), script: String = "exit 0") -> TerminalSessionController {
        let launch = ShellLaunch(executable: "/bin/sh", arguments: ["-c", script],
                                 environment: ["PATH=/usr/bin:/bin"], kind: .other)
        return TerminalSessionController(sessionID: SessionID(), launch: launch,
                                         workingDirectory: URL(fileURLWithPath: "/tmp"), bus: bus)
    }

    private func waitForExit(_ c: TerminalSessionController) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .exited = c.state { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testApplyingAppearanceSetsColorsFontAndCursor() {
        let controller = makeController()
        let theme = ThemeLoader(userDirectory: nil).resolve(name: "gruvbox-dark", preferDark: true)
        let font = NSFont(name: "Menlo", size: 15)!
        controller.apply(TerminalAppearance(theme: theme, font: font, cursorStyle: .steadyBar))
        let view = controller.view
        XCTAssertEqual(view.font.pointSize, 15)
        XCTAssertEqual(view.nativeBackgroundColor.hexRGB, theme.background.hex)
        XCTAssertEqual(view.nativeForegroundColor.hexRGB, theme.foreground.hex)
        XCTAssertEqual(view.caretColor.hexRGB, theme.cursor.hex)
        XCTAssertEqual(view.getTerminal().options.cursorStyle, .steadyBar)
    }

    func testAppearanceKeepsBackgroundOpacity() {
        let controller = makeController()
        controller.view.backgroundOpacity = 0.6
        let theme = ThemeLoader(userDirectory: nil).resolve(name: "ante-dark", preferDark: true)
        controller.apply(TerminalAppearance(theme: theme, font: NSFont(name: "Menlo", size: 13)!, cursorStyle: .blinkBlock))
        XCTAssertEqual(controller.view.backgroundOpacity, 0.6, accuracy: 0.01)
    }

    func testActivityFollowsCommandEvents() async {
        let script = "printf '\\033]133;C\\007'; sleep 0.3; printf '\\033]133;D;2\\007'; exit 0"
        let controller = makeController(script: script)
        controller.start()
        let deadline = Date().addingTimeInterval(3)
        var sawRunning = false
        while Date() < deadline {
            if controller.activity == .commandRunning { sawRunning = true }
            if controller.lastExitCode == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(sawRunning)
        XCTAssertEqual(controller.lastExitCode, 2)
        XCTAssertEqual(controller.activity, .idle)
        await waitForExit(controller)
    }
}

private extension NSColor {
    var hexRGB: String {
        let c = usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
