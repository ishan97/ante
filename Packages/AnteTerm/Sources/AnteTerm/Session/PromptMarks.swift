// Packages/AnteTerm/Sources/AnteTerm/Session/PromptMarks.swift
import Foundation
import SwiftTerm

public struct PromptMark: Equatable, Sendable {
    /// Buffer-absolute row (scrollback included).
    public let row: Int
    public let exitCode: Int?
}

/// Prompt positions come from SwiftTerm, which tags every OSC 133;A row and keeps the tag through
/// scrollback trimming and reflow (`semanticRowKind(at:) == .initial`). What SwiftTerm does not
/// know is the exit code, so that is remembered here, keyed by the identity of the `BufferLine`
/// the prompt was drawn on. A recycled line that becomes a prompt again could show a stale code;
/// the window for that is one full scrollback of output, and the mark itself is still correct.
/// `record`/`attachExitCode`/`invalidateAll` run on SwiftTerm's process queue; `marks(in:)` runs
/// on main. A row is drawn only if it is tagged by SwiftTerm *and* was recorded here at its
/// `133;A` — SwiftTerm keeps tags through `clear` (ED), so a redrawn prompt on an old row would
/// otherwise inherit a stale mark. `invalidateAll` runs on every screen clear.
final class PromptMarks: @unchecked Sendable {
    private let lock = NSLock()
    private var exitCodes: [ObjectIdentifier: Int?] = [:]
    private var order: [ObjectIdentifier] = []
    private let capacity = 2_000

    func invalidateAll() {
        lock.withLock {
            exitCodes.removeAll()
            order.removeAll()
        }
    }

    func record(prompt line: BufferLine) {
        let id = ObjectIdentifier(line)
        lock.withLock {
            if exitCodes[id] == nil {
                order.append(id)
                if order.count > capacity {
                    exitCodes[order.removeFirst()] = nil
                }
            }
            exitCodes[id] = .some(nil)
        }
    }

    /// The exit code of a command belongs to the prompt that issued it: the most recent one.
    func attachExitCode(_ code: Int?) {
        lock.withLock {
            guard let last = order.last else { return }
            exitCodes[last] = .some(code)
        }
    }

    /// Prompt rows within `range` (clamped to the buffer), top to bottom.
    func marks(in range: Range<Int>, terminal: Terminal) -> [PromptMark] {
        var out: [PromptMark] = []
        var row = max(0, range.lowerBound)
        while row < range.upperBound, let line = terminal.bufferLine(atRow: row) {
            // `clear` (ED) blanks the cells but SwiftTerm keeps the row's prompt tag; a prompt row
            // is never empty, so an empty tagged row is stale and must not be drawn.
            if terminal.semanticRowKind(at: row) == .initial, !line.translateToString(trimRight: true).isEmpty,
               let recorded = lock.withLock({ exitCodes[ObjectIdentifier(line)] }) {
                out.append(PromptMark(row: row, exitCode: recorded))
            }
            row += 1
        }
        return out
    }

    /// Nearest prompt row strictly above `row`.
    func previousPrompt(before row: Int, terminal: Terminal) -> Int? {
        var r = row - 1
        while r >= 0 {
            if isLivePrompt(row: r, terminal: terminal) { return r }
            r -= 1
        }
        return nil
    }

    private func isLivePrompt(row: Int, terminal: Terminal) -> Bool {
        guard terminal.semanticRowKind(at: row) == .initial, let line = terminal.bufferLine(atRow: row) else { return false }
        guard !line.translateToString(trimRight: true).isEmpty else { return false }
        return lock.withLock { exitCodes[ObjectIdentifier(line)] != nil }
    }

    /// Nearest prompt row strictly below `row`.
    func nextPrompt(after row: Int, terminal: Terminal) -> Int? {
        var r = row + 1
        while terminal.bufferLine(atRow: r) != nil {
            if isLivePrompt(row: r, terminal: terminal) { return r }
            r += 1
        }
        return nil
    }

    /// One past the last buffer row.
    func bufferEnd(terminal: Terminal) -> Int {
        var r = terminal.getTopVisibleRow()
        while terminal.bufferLine(atRow: r) != nil { r += 1 }
        return r
    }
}
