// Packages/AnteUI/Tests/AnteUITests/BugReviewTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class BugReviewTests: XCTestCase {
    private func makeRuntime() -> (WorkspaceRuntime, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-bug-\(UUID().uuidString)")
        let paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
        return (runtime, root)
    }

    /// Bug review #1: asking for a stale pane must not spawn a shell or register a pane.
    func testControllerForUnknownPaneNeverSpawns() {
        let (runtime, root) = makeRuntime()
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let stale = PaneID()
        let placeholder = runtime.controller(for: stale)
        XCTAssertEqual(placeholder.state, .idle)
        XCTAssertNil(runtime.session(for: stale))
        XCTAssertTrue(runtime.controller(for: stale) === placeholder, "stable placeholder, no churn")
    }

    /// Bug review #5: ⌘-click never executes a path.
    func testLinkOpenerNeverExecutes() {
        let script = LinkDetector.Match(range: 0..<10, kind: .path("/tmp/deploy.sh", line: nil))
        XCTAssertEqual(LinkOpener.plan(for: script, isDirectory: { _ in false }), .editFile("/tmp/deploy.sh"))
        let dir = LinkDetector.Match(range: 0..<4, kind: .path("/tmp", line: nil))
        XCTAssertEqual(LinkOpener.plan(for: dir, isDirectory: { _ in true }), .revealDirectory("/tmp"))
        let fileURL = LinkDetector.Match(range: 0..<10, kind: .url(URL(string: "file:///usr/bin/python3")!))
        XCTAssertEqual(LinkOpener.plan(for: fileURL, isDirectory: { _ in false }), .editFile("/usr/bin/python3"))
        let web = LinkDetector.Match(range: 0..<10, kind: .url(URL(string: "https://example.com")!))
        XCTAssertEqual(LinkOpener.plan(for: web), .browse(URL(string: "https://example.com")!))
    }

    /// Closing a non-focused pane by ID keeps focus where it was; closing the focused one moves it.
    func testClosePaneByID() {
        let (runtime, root) = makeRuntime()
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let session = runtime.store.focusedSession!
        runtime.open(session: session.id)
        let first = runtime.focusedPaneID!
        runtime.splitFocusedPane(axis: .horizontal, before: true)   // new pane on the left, focused
        let left = runtime.focusedPaneID!
        XCTAssertEqual(runtime.layout(for: session.id).paneIDs, [left, first])
        XCTAssertEqual(runtime.paneCount(for: session.id), 2)
        runtime.closePane(first)                                     // close the unfocused one
        XCTAssertEqual(runtime.focusedPaneID, left)
        XCTAssertEqual(runtime.paneCount(for: session.id), 1)
        XCTAssertNil(runtime.session(for: first))
    }

    /// Closing a session removes its panes, controllers, and layout; nothing lingers.
    func testCloseSessionCleansUp() {
        let (runtime, root) = makeRuntime()
        defer { runtime.prepareForQuit(); try? FileManager.default.removeItem(at: root) }
        let project = runtime.store.state.projects[0]
        let session = runtime.newSession(in: project.id)
        let pane = runtime.focusedPaneID!
        runtime.closeSession(session.id)
        XCTAssertNil(runtime.existingLayout(for: session.id))
        XCTAssertNil(runtime.session(for: pane))
        XCTAssertFalse(runtime.store.state.sessions.contains { $0.id == session.id })
    }
}
