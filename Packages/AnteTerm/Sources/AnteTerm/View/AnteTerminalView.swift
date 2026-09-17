// Packages/AnteTerm/Sources/AnteTerm/View/AnteTerminalView.swift
import AppKit
import SwiftTerm
import AnteCore

/// SwiftTerm's local-process terminal view with Ante's additions: a PTY byte tee for OSC 133/7,
/// ⌘-click on links and paths, multi-line paste confirmation, and scroll/content hooks.
///
/// `dataReceived` is called on SwiftTerm's process queue, not the main thread. The scanner is
/// guarded by a lock and `onSemanticEvents` is invoked on that same queue.
public final class AnteTerminalView: LocalProcessTerminalView {
    private let scannerLock = NSLock()
    private var scanner = OSCScanner()
    private let parser = SemanticPromptParser()

    /// Called on the process queue with every batch of semantic events found in one PTY read.
    public var onSemanticEvents: (([SemanticEvent]) -> Void)?
    /// Called on the process queue for `promptStarted` / `commandFinished` at the exact moment the
    /// terminal has consumed the bytes up to that sequence — so buffer positions are precise.
    public var onSemanticEventSync: ((SemanticEvent) -> Void)?
    /// Called on the process queue after the terminal consumed an `ESC[2J`, `ESC[3J`, or `ESC c`
    /// (full reset): prompt marks recorded so far are stale.
    public var onScreenCleared: (() -> Void)?
    /// Called on the main thread when the user ⌘-clicks a detected link or path.
    public var onOpenLink: ((LinkDetector.Match) -> Void)?
    /// The shell's working directory, for resolving `./` and `../` paths in output. Set by the controller.
    public var linkBaseDirectory: URL?
    /// Called on the main thread after scrolling or new output (coalesced by the caller).
    public var onScrollOrContentChange: (() -> Void)?
    /// Called on the process queue for every PTY read (output arrived). Cheap; callers coalesce.
    public var onOutput: (() -> Void)?
    /// Called on the main thread when the user types or pastes into this terminal.
    public var onUserInput: (() -> Void)?
    /// Called on the main thread when the view (re)joins a window. Programs redraw on attach and
    /// resize, so the output that follows says nothing about whether they are busy.
    public var onAttached: (() -> Void)?
    /// Ask before pasting text containing a newline (the classic curl-pipe-sh defence).
    public var confirmMultilinePaste = true
    /// Set by the host when this pane is the focused one. The view then takes the keyboard as
    /// soon as it has a window, and on any click — unless the user is typing in a text field.
    public var claimsKeyboardWhenFocused = false {
        didSet { claimKeyboardIfAppropriate() }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimKeyboardIfAppropriate()
        if window != nil {
            installKeyMonitor()
            registerForDraggedTypes([.fileURL])
            onAttached?()
        }
    }

    // MARK: - Files

    /// Types the given files as shell-quoted paths at the cursor, like dropping them on Terminal.app.
    public func insertPaths(_ urls: [URL]) {
        let line = ShellQuote.line(for: urls)
        guard !line.isEmpty else { return }
        onUserInput?()
        send(txt: line)
    }

    private static func fileURLs(in info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(in: sender).isEmpty ? [] : .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(in: sender).isEmpty ? [] : .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        insertPaths(urls)
        window?.makeFirstResponder(self)
        return true
    }

    // `keyDown` is not overridable in SwiftTerm, so keystrokes are observed with a local monitor
    // that only reports events this view will receive.
    nonisolated(unsafe) private var keyMonitor: Any?

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self, event.window === self.window, self.window?.firstResponder === self { self.onUserInput?() }
            return event
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    public func claimKeyboardIfAppropriate() {
        guard claimsKeyboardWhenFocused, let window, window.firstResponder !== self else { return }
        if window.firstResponder is NSTextView { return }   // search bar, palette, rename field
        window.makeFirstResponder(self)
    }

    public override func dataReceived(slice: ArraySlice<UInt8>) {
        onOutput?()
        let found = scannerLock.withLock { scanner.scanWithEnds(slice) }
        let events = found.compactMap { parser.parse($0.sequence) }
        if !events.isEmpty {
            onSemanticEvents?(events)
        }
        guard onSemanticEventSync != nil else {
            super.dataReceived(slice: slice)
            if Self.containsScreenClear(slice) { onScreenCleared?() }
            return
        }
        // Feed in pieces so position-sensitive events see the buffer as it was right after them.
        var cursor = slice.startIndex
        for (sequence, end) in found {
            guard let event = parser.parse(sequence), Self.isPositionSensitive(event) else { continue }
            let boundary = slice.startIndex + end
            if boundary > cursor {
                super.dataReceived(slice: slice[cursor..<boundary])
                cursor = boundary
            }
            onSemanticEventSync?(event)
        }
        if cursor < slice.endIndex {
            super.dataReceived(slice: slice[cursor..<slice.endIndex])
        }
        if Self.containsScreenClear(slice) {
            onScreenCleared?()
        }
    }

    /// `ESC [ 2 J`, `ESC [ 3 J`, or `ESC c`. A sequence split across two reads is missed; the next
    /// prompt's `133;A` re-records correctly anyway, so the cost is one stale dot at worst.
    static func containsScreenClear(_ bytes: ArraySlice<UInt8>) -> Bool {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            if bytes[i] == 0x1B {
                let next = bytes.index(after: i)
                guard next < bytes.endIndex else { return false }
                if bytes[next] == 0x63 { return true }                       // ESC c
                if bytes[next] == 0x5B {                                      // ESC [
                    let a = bytes.index(after: next)
                    if a < bytes.endIndex, bytes[a] == 0x32 || bytes[a] == 0x33 {   // 2 or 3
                        let b = bytes.index(after: a)
                        if b < bytes.endIndex, bytes[b] == 0x4A { return true }     // J
                    }
                }
            }
            i = bytes.index(after: i)
        }
        return false
    }

    private static func isPositionSensitive(_ event: SemanticEvent) -> Bool {
        switch event {
        case .promptStarted, .commandFinished: return true
        case .commandStarted, .cwdChanged, .notification: return false
        }
    }

    // MARK: - Geometry

    /// The cell size SwiftTerm uses, derived the same way it does (font ascent + descent + leading,
    /// rounded up; width from the advancement of a wide ASCII glyph). The grid is pinned to the
    /// top-left, with slack at the bottom/right — so dividing the bounds by rows/cols would drift.
    public func cellSize() -> CGSize {
        let ctFont = font as CTFont
        let height = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        var glyph: CGGlyph = 0
        var char: UniChar = 0x57   // "W"
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var width = ceil(font.pointSize * 0.6)
        if CTFontGetGlyphsForCharacters(ctFont, &char, &glyph, 1) {
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
            if advance.width > 0 { width = (advance.width * scale).rounded() / scale }   // pixel-snapped, as SwiftTerm does
        }
        return CGSize(width: max(1, width), height: max(1, ceil(height * scale) / scale))
    }

    /// Grid position for a point in this view's coordinates. Row is buffer-absolute.
    public func gridPosition(for point: CGPoint) -> (row: Int, col: Int) {
        let cell = cellSize()
        let col = max(0, Int(point.x / cell.width))
        let fromTop = isFlipped ? point.y : (bounds.height - point.y)
        let visibleRow = max(0, Int(fromTop / cell.height))
        return (getTerminal().getTopVisibleRow() + visibleRow, col)
    }

    // MARK: - Links

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let match = linkMatch(at: event) {
            onOpenLink?(match)
            return
        }
        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    private func linkMatch(at event: NSEvent) -> LinkDetector.Match? {
        let point = convert(event.locationInWindow, from: nil)
        let (row, col) = gridPosition(for: point)
        let terminal = getTerminal()
        guard let line = terminal.bufferLine(atRow: row) else { return nil }
        let text = line.translateToString(trimRight: true)
        return LinkDetector.match(in: text, atColumn: col, relativeTo: linkBaseDirectory)
    }

    // MARK: - Paste

    public override func paste(_ sender: Any) {
        guard confirmMultilinePaste,
              let text = NSPasteboard.general.string(forType: .string),
              text.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            superPaste(sender)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Paste \(text.split(whereSeparator: \.isNewline).count) lines?"
        alert.informativeText = "The clipboard contains multiple lines. Pasting runs each line as it is entered.\n\n" + String(text.prefix(400))
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.superPaste(sender) }
        }
    }

    private func superPaste(_ sender: Any) {
        onUserInput?()
        super.paste(sender)
    }

    // MARK: - Hooks

    public override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        onScrollOrContentChange?()
    }

    public override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        onScrollOrContentChange?()
    }
}
