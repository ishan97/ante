// Packages/AnteTerm/Sources/AnteTerm/Session/TerminalSessionController+Navigation.swift
import AppKit
import SwiftTerm
import AnteCore

public enum PromptDirection: Sendable { case previous, next }
public enum SearchDirection: Sendable { case previous, next }

extension TerminalSessionController {
    /// Every prompt mark in the buffer, top to bottom. Scans the whole buffer; use `marks(in:)`
    /// for the visible range when drawing.
    public var marks: [PromptMark] {
        promptMarks.marks(in: 0..<Int.max, terminal: view.getTerminal())
    }

    public func marks(in range: Range<Int>) -> [PromptMark] {
        promptMarks.marks(in: range, terminal: view.getTerminal())
    }

    public var topVisibleRow: Int { view.getTerminal().getTopVisibleRow() }
    public var rows: Int { view.getTerminal().rows }

    public func jumpToPrompt(direction: PromptDirection) {
        let terminal = view.getTerminal()
        let current = topVisibleRow
        let target: Int?
        switch direction {
        case .previous: target = promptMarks.previousPrompt(before: current, terminal: terminal)
        case .next: target = promptMarks.nextPrompt(after: current, terminal: terminal)
        }
        guard let target else { return }
        view.scrollTo(row: target)
    }

    /// Selects the output of the most recent command whose prompt is on or above the last visible
    /// row. Output = rows after the prompt row, up to the next prompt (or the buffer end).
    public func selectPreviousCommandOutput() {
        let terminal = view.getTerminal()
        let lastVisible = topVisibleRow + rows - 1
        // The prompt currently awaiting input has no output; start from the prompt before it.
        guard let waiting = promptMarks.previousPrompt(before: lastVisible + 1, terminal: terminal) else { return }
        let promptRow = promptMarks.previousPrompt(before: waiting, terminal: terminal) ?? waiting
        let startRow = promptRow + 1
        let endRow = (promptMarks.nextPrompt(after: promptRow, terminal: terminal) ?? promptMarks.bufferEnd(terminal: terminal)) - 1
        guard endRow >= startRow else { return }
        view.selection.setSelection(start: Position(col: 0, row: startRow),
                                    end: Position(col: max(0, terminal.cols - 1), row: endRow))
        view.scrollTo(row: max(0, promptRow))
    }

    @discardableResult
    public func search(_ term: String, caseSensitive: Bool = false, direction: SearchDirection) -> (index: Int, total: Int) {
        let options = SearchOptions(caseSensitive: caseSensitive, regex: false, wholeWord: false)
        guard !term.isEmpty else { view.clearSearch(); return (0, 0) }
        switch direction {
        case .next: _ = view.findNext(term, options: options, scrollToResult: true)
        case .previous: _ = view.findPrevious(term, options: options, scrollToResult: true)
        }
        return view.searchMatchSummary(term, options: options)
    }

    public func clearSearch() {
        view.clearSearch()
    }

    /// ⌘K: wipe the screen and scrollback locally (ESC[3J ESC[H ESC[2J), then, if the shell is
    /// sitting at a prompt, ask it to redraw with ^L so the prompt reappears at the top.
    public func clearScreen() {
        promptMarks.invalidateAll()
        view.feed(text: "\u{1b}[3J\u{1b}[H\u{1b}[2J")
        if state == .running, activity == .idle {
            view.send(txt: "\u{0c}")
        }
        contentDidChange()   // the gutter must drop its dots now, not at the next prompt
    }
}
