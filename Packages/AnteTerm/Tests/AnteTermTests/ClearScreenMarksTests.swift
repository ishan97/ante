// Packages/AnteTerm/Tests/AnteTermTests/ClearScreenMarksTests.swift
// Regression: ⌘K must leave no prompt marks for rows it blanked.
import XCTest
import AnteCore
@testable import AnteTerm

@MainActor
final class ClearScreenMarksTests: XCTestCase {
    private func makeController(script: String) -> TerminalSessionController {
        TerminalSessionController(sessionID: SessionID(),
                                  launch: ShellLaunch(executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH=/usr/bin:/bin"], kind: .other),
                                  workingDirectory: URL(fileURLWithPath: "/tmp"), bus: RunEventBus())
    }

    func testClearScreenLeavesNoStaleMarks() async throws {
        let prompt = "printf '\\033]133;A\\007$ '"
        let run = { (cmd: String, code: Int) in "printf '\(cmd)\\n'; printf '\\033]133;C\\007'; echo out-\(cmd); printf '\\033]133;D;\(code)\\007'; " }
        let script = prompt + "; " + run("one", 0) + prompt + "; " + run("two", 1) + prompt + "; " + run("three", 0) + prompt + "; sleep 1.2; "
            + "printf '\\033[H\\033[2J'; " + prompt + "; sleep 1; exit 0"
        let controller = makeController(script: script)
        controller.start()
        try await Task.sleep(for: .milliseconds(700))
        let before = controller.marks
        controller.clearScreen()   // ⌘K: local clear, then ^L to the shell (the script "redraws" a prompt itself)
        try await Task.sleep(for: .seconds(2))
        let terminal = controller.view.getTerminal()
        var dump = "before=\(before.map { "\($0.row):\($0.exitCode.map(String.init) ?? "nil")" })\n"
        dump += "after=\(controller.marks.map { "\($0.row):\($0.exitCode.map(String.init) ?? "nil")" }) top=\(controller.topVisibleRow) rows=\(controller.rows)\n"
        for row in 0..<min(14, controller.rows + controller.topVisibleRow) {
            if let line = terminal.bufferLine(atRow: row) {
                dump += "row \(row) kind=\(terminal.semanticRowKind(at: row)) text=\(line.translateToString(trimRight: true).debugDescription)\n"
            }
        }
        print("DUMP\n" + dump)
        XCTAssertLessThanOrEqual(controller.marks.count, 1, dump)
    }
}
