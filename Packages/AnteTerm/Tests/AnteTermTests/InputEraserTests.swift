import XCTest
import AppKit
import AnteCore
@testable import AnteTerm

/// ⌘⌫ erases the whole draft without Esc, in the keys each program understands.
final class InputEraserTests: XCTestCase {
    private let round: [UInt8] = [0x0B, 0x15, 0x7F, 0x1B, 0x5B, 0x33, 0x7E]   // ⌃K ⌃U ⌫ ESC[3~

    func testDraftAgentsGetLineClearsInWritesClaudeCanRead() {
        for agent in [AgentKind.claude, .codex] {
            let chunks = InputEraser.chunks(for: agent, commandLine: [agent.rawValue])
            let bytes = chunks.flatMap { $0 }
            XCTAssertEqual(bytes.count % round.count, 0)
            XCTAssertGreaterThanOrEqual(bytes.count / round.count * 2, 64, "covers a 64-line draft")
            for chunk in chunks {
                XCTAssertEqual(chunk.count % round.count, 0, "a chunk never splits a round (or ESC[3~)")
                // Probed against Claude Code 2.1.316: 56 bytes in one read are handled, 84 are not.
                // Two chunks merged into one read must stay within that.
                XCTAssertLessThanOrEqual(chunk.count * 2, 56)
            }
            XCTAssertEqual(Array(bytes.prefix(round.count)), round)
        }
    }

    func testNeverSendsEscCtrlCOrCtrlD() {
        // Esc interrupts a running agent; ⌃C interrupts or quits; ⌃D quits on an empty line.
        for agent in AgentKind.allCases {
            let bytes = InputEraser.chunks(for: agent, commandLine: [agent.rawValue]).flatMap { $0 }
            XCTAssertFalse(bytes.contains(0x03), "\(agent)")
            XCTAssertFalse(bytes.contains(0x04), "\(agent)")
            var i = 0
            while i < bytes.count {
                if bytes[i] == 0x1B {   // only as the start of ESC[3~ (forward delete)
                    XCTAssertEqual(Array(bytes[i..<min(i + 4, bytes.count)]), [0x1B, 0x5B, 0x33, 0x7E], "\(agent)")
                    i += 4
                } else {
                    i += 1
                }
            }
        }
    }

    func testShellsKillTheWholeLine() {
        XCTAssertEqual(InputEraser.chunks(for: .shell), [[0x05, 0x15]])
    }

    func testUnprobedAgentsAndOtherProgramsGetCtrlUOnlyLikeITerm() {
        for agent in [AgentKind.aider, .gemini, .goose, .amp, .opencode, .cursor, .pi, .command] {
            XCTAssertEqual(InputEraser.chunks(for: agent), [[0x15]], "\(agent)")
        }
    }

    func testOneShotRunsReadNoKeysSoGetNoDraftRounds() {
        // The rounds would sit in the tty and reach the shell once the run ends.
        for argv in [["claude", "-p", "hi"], ["claude", "--print", "hi"], ["claude", "mcp", "serve"],
                     ["node", "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js", "mcp", "serve"],
                     ["codex", "exec", "fix it"], ["codex", "e", "fix it"], ["codex", "mcp-server"]] {
            let agent = AgentKind.classify(commandLine: argv)
            XCTAssertEqual(InputEraser.chunks(for: agent, commandLine: argv), [[0x15]], "\(argv)")
        }
        for argv in [["claude"], ["claude", "--resume", "abc"], ["claude", "fix the tests"], ["claude", "--model", "opus"],
                     ["/Users/me/.local/bin/claude", "-c"], ["codex"], ["codex", "resume", "abc"],
                     ["node", "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"]] {
            let agent = AgentKind.classify(commandLine: argv)
            XCTAssertGreaterThan(InputEraser.chunks(for: agent, commandLine: argv).count, 1, "\(argv)")
        }
    }

    // MARK: - The key

    private func key(_ characters: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func testOnlyPlainCommandDeleteErases() {
        XCTAssertTrue(AnteTerminalView.isEraseInput(key("\u{7F}", .command, keyCode: 51)))
        XCTAssertTrue(AnteTerminalView.isEraseInput(key("\u{7F}", [.command, .capsLock], keyCode: 51)))
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("\u{7F}", [], keyCode: 51)))               // ⌫
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("\u{7F}", .option, keyCode: 51)))          // ⌥⌫ deletes a word
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("\u{7F}", [.command, .shift], keyCode: 51)))
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("\u{7F}", [.command, .option], keyCode: 51)))
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("k", .command, keyCode: 40)))               // ⌘K
        XCTAssertFalse(AnteTerminalView.isEraseInput(key("\u{F728}", .command, keyCode: 117)))      // ⌘⌦
    }
}
