// Packages/AnteTerm/Tests/AnteTermTests/PromptMarksTests.swift
import XCTest
import AnteCore
@testable import AnteTerm

@MainActor
final class PromptMarksTests: XCTestCase {
    private func makeController(script: String) -> TerminalSessionController {
        let launch = ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        return TerminalSessionController(sessionID: SessionID(), launch: launch, workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
    }

    private func waitForExit(_ c: TerminalSessionController) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .exited = c.state { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Two prompts, one command between them that exits 7; marks must land on the prompt rows.
    func testMarksRecordPromptRowsAndExitCodes() async {
        let script = """
        printf '\\033]133;A\\007$ \\033]133;B\\007'; printf 'ls\\n'; printf '\\033]133;C\\007'; printf 'out1\\nout2\\n'; \
        printf '\\033]133;D;7\\007'; printf '\\033]133;A\\007$ \\033]133;B\\007'; sleep 0.3
        """
        let controller = makeController(script: script)
        controller.start()
        await waitForExit(controller)
        let marks = controller.marks
        XCTAssertEqual(marks.map(\.row), [0, 3], "\(marks)")
        XCTAssertEqual(marks.map(\.exitCode), [7, nil])
    }

    func testClearRemovesStaleMarks() async {
        let script = "printf '\\033]133;A\\007$ \\033]133;B\\007'; printf 'x\\n'; printf '\\033]133;C\\007'; printf '\\033]133;D;0\\007'; " +
                     "printf '\\033]133;A\\007$ \\033]133;B\\007'; sleep 0.3"
        let controller = makeController(script: script)
        controller.start()
        await waitForExit(controller)
        XCTAssertEqual(controller.marks.count, 2)
        controller.clearScreen()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.marks.isEmpty, "\(controller.marks)")
    }

    /// `clear` blanks cells but SwiftTerm keeps row tags; a prompt redrawn on an old row must not
    /// show a stale mark, and the next real prompt must.
    func testShellClearForgetsStaleMarksUntilNextPrompt() async {
        var script = "printf '\\033]133;A\\007$ \\033]133;B\\007'; printf 'ls\\n'; printf '\\033]133;C\\007'; "
        script += "for i in 1 2 3 4 5; do printf 'line\\n'; done; printf '\\033]133;D;0\\007'; "
        script += "printf '\\033]133;A\\007$ \\033]133;B\\007'; sleep 0.2; "
        script += "printf '\\033[H\\033[2J\\033[3J'; printf '$ \\033]133;B\\007'; sleep 0.2; "
        script += "printf 'MARKER\\n'; sleep 0.2"
        let controller = makeController(script: script)
        controller.start()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline, !String(decoding: controller.view.getTerminal().getBufferAsData(), as: UTF8.self).contains("MARKER") {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(controller.marks.isEmpty, "redrawn prompt on an old row must not carry a mark: \(controller.marks)")
        await waitForExit(controller)
    }

    func testFreshPromptAfterClearIsMarked() async {
        var script = "printf '\\033]133;A\\007$ \\033]133;B\\007'; printf 'ls\\n'; printf '\\033]133;C\\007'; printf '\\033]133;D;0\\007'; "
        script += "printf '\\033[H\\033[2J\\033[3J'; sleep 0.2; "
        script += "printf '\\033]133;A\\007$ \\033]133;B\\007'; sleep 0.3"
        let controller = makeController(script: script)
        controller.start()
        await waitForExit(controller)
        XCTAssertEqual(controller.marks.map(\.row), [0])
        XCTAssertEqual(controller.marks.first?.exitCode, nil, "new prompt, no command yet")
    }

    func testJumpAndSelectOutput() async {
        var script = ""
        for i in 0..<40 {
            script += "printf '\\033]133;A\\007$ \\033]133;B\\007'; printf 'cmd\\(i)\\n'; printf '\\033]133;C\\007'; printf 'line a\\nline b\\n'; printf '\\033]133;D;0\\007'; "
        }
        script += "sleep 0.3"
        let controller = makeController(script: script.replacingOccurrences(of: "\\(i)", with: "N"))
        controller.start()
        await waitForExit(controller)
        XCTAssertEqual(controller.marks.count, 40)
        let bottom = controller.topVisibleRow
        controller.jumpToPrompt(direction: .previous)
        XCTAssertLessThan(controller.topVisibleRow, bottom)
        controller.selectPreviousCommandOutput()
        XCTAssertTrue(controller.view.selectionActive)
        XCTAssertEqual(controller.view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines), "line a\nline b")
    }

    func testSearchWrappers() async {
        let controller = makeController(script: "printf 'alpha\\nbeta\\nalpha again\\n'; sleep 0.2")
        controller.start()
        await waitForExit(controller)
        let first = controller.search("alpha", direction: .next)
        XCTAssertEqual(first.total, 2)
        XCTAssertEqual(first.index, 1)
        let second = controller.search("alpha", direction: .next)
        XCTAssertEqual(second.index, 2)
        XCTAssertEqual(controller.search("zzz", direction: .next).total, 0)
        controller.clearSearch()
    }
}
