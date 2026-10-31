import XCTest
import AppKit
import SwiftUI
@testable import AnteUI
import AnteCore

/// Drives the real token popover in a real NSPopover the way clicking does: every window, over
/// and over, with reports arriving in between (empty, quiet, busy, with agents and models coming
/// and going). It must neither crash nor change height when only the window changes.
@MainActor
final class TokenPopoverStressTests: XCTestCase {
    private func report(agents: [AgentKind], models: Int, now: Date) -> TokenUsageReport {
        var records: [TokenRecord] = []
        for (i, agent) in agents.enumerated() {
            for m in 0..<models {
                // Like real logs: later agents and models only show up in the longer windows.
                for days in [0.2, 3, 20, 45, 80, 150, 300].dropFirst((i + m) % 7) {
                    records.append(TokenRecord(at: now.addingTimeInterval(-days * 86400), agent: agent, model: "model-\(i)-\(m)",
                                               count: TokenCount(input: 1_000 * (m + 1), output: 7, cacheRead: Int(days) * 31, cacheWrite: 3)))
                }
            }
        }
        return TokenUsageReport.build(records: records, now: now)
    }

    func testClickingThroughEveryWindowNeverResizesOrCrashes() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 280, y: 360, width: 30, height: 20))
        window.contentView?.addSubview(anchor)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let model = TokenUsageModel(ledger: TokenLedger(sources: TokenLedger.Sources(
            claudeProjects: URL(fileURLWithPath: "/nonexistent"), codexRoots: [], openCodeDatabase: URL(fileURLWithPath: "/nonexistent"),
            piSessions: URL(fileURLWithPath: "/nonexistent"), geminiTmp: URL(fileURLWithPath: "/nonexistent"))))
        let host = NSHostingController(rootView: TokenUsageView(model: model))
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.contentViewController = host
        popover.animates = true
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { popover.close() }

        func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        let now = Date()
        let reports: [TokenUsageReport?] = [
            nil,
            TokenUsageReport.build(records: [], now: now),
            report(agents: [.claude], models: 1, now: now),
            report(agents: [.claude, .codex], models: 3, now: now),
            report(agents: [.claude, .codex, .opencode, .pi, .gemini], models: 9, now: now),
            report(agents: [.codex], models: 6, now: now),
        ]
        var rounds = 0
        for next in reports + reports.reversed() {
            // A report arriving the way the background refresh delivers it, inside an animation.
            withAnimation(.easeOut(duration: 0.25)) { model.report = next }
            spin()
            var heights = Set<Int>()
            for _ in 0..<4 {
                for window in TokenUsageReport.Window.allCases.shuffled() {
                    withAnimation(.easeOut(duration: 0.15)) { model.selected = window }
                    spin()
                    heights.insert(Int(host.view.fittingSize.height.rounded()))
                    rounds += 1
                }
            }
            if next != nil {
                XCTAssertEqual(heights.count, 1, "picking a window changed the popover's height: \(heights)")
            }
        }
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(rounds, reports.count * 2 * 4 * TokenUsageReport.Window.allCases.count)
    }
}
