// Packages/AntePanel/Sources/AntePanel/HotkeyWindowToggler.swift
import AppKit
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    /// ⌥` by default. Users change it in Settings via `KeyboardShortcuts.Recorder`.
    /// (The stored key keeps its original name so existing custom shortcuts survive.)
    public static let showHideAnte = Self("toggleScratchPanel", initial: .init(.backtick, modifiers: .option))
}

/// The global hotkey, floating-window style: one press drops the workspace window over
/// whatever you are doing — on this Space, above every other window — and makes Ante the active
/// app (its name in the menu bar, its shortcuts live). The next press (or, optionally, clicking
/// away) slides it out again and hands control back to the app you came from. Nothing else on
/// screen moves, and the window's contents are untouched either way.
@MainActor
public final class HotkeyWindowToggler {
    /// Mirrors `[hotkey] animation`; mapped from the config by the app.
    public enum Reveal: String, Sendable { case fade, slideDown, slideUp, slideLeft, slideRight, none }

    private static let logger = Logger(subsystem: "ante.term", category: "hotkey")
    public weak var window: NSWindow?
    public var hideOnFocusLoss: Bool
    public var reveal: Reveal
    /// Called before the window slides away, so the app can leave any state (⌘↩ full screen)
    /// that should not survive being hidden.
    public var onWillHide: (() -> Void)?
    /// Overlay size as fractions of the screen's visible area; docked top, centred.
    public var overlayWidth: Double = 0.9 { didSet { if overlayWidth != oldValue { summonedFrame = nil } } }
    public var overlayHeight: Double = 0.6 { didSet { if overlayHeight != oldValue { summonedFrame = nil } } }
    /// Where the window was when it was last hidden. The next summon puts it right back there —
    /// the configured overlay geometry is only the starting point, and a change to it resets this.
    private var summonedFrame: NSRect?
    /// The window's everyday Space behaviour, put back when it hides.
    private var restoreBehavior: NSWindow.CollectionBehavior?
    /// The app you came from, so hiding can hand focus back if Ante ended up active meanwhile.
    private var previousApp: NSRunningApplication?

    /// While summoned: on every Space, including over another app's full-screen window, so
    /// macOS never switches Spaces to show it.
    public static let summonedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    /// While summoned: just below the menu bar (menu bar − 2, the level other terminals' hotkey windows use, observed with
    /// CGWindowList), so neither is stuck under the other — whichever hotkey was pressed last is
    /// on top, and both stay below the menu bar and Dock.
    public static let summonedLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 2)
    /// Set by the hotkey, cleared when the window hides or loses the keyboard. Only a summoned
    /// window floats above other apps.
    public private(set) var isSummoned = false
    private var isAnimating = false
    private var resignObserver: NSObjectProtocol?

    public init(window: NSWindow? = nil, hideOnFocusLoss: Bool, reveal: Reveal = .slideDown) {
        self.window = window
        self.hideOnFocusLoss = hideOnFocusLoss
        self.reveal = reveal
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.windowDidResignKey() }
        }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    public func installGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .showHideAnte) { [weak self] in
            self?.toggle()
        }
    }

    /// Hide when the window is showing and has the keyboard; otherwise summon it.
    public static func shouldHide(windowVisible: Bool, windowKey: Bool) -> Bool {
        windowVisible && windowKey
    }

    /// The summoned window's frame: a fraction of the visible screen, flush with its top edge.
    public static func overlayFrame(in visible: NSRect, width: Double, height: Double) -> NSRect {
        let w = (visible.width * min(max(width, 0.3), 1)).rounded()
        let h = (visible.height * min(max(height, 0.3), 1)).rounded()
        return NSRect(x: (visible.midX - w / 2).rounded(), y: visible.maxY - h, width: w, height: h)
    }

    /// Where the window starts (or ends) for a reveal, just outside the screen edge it enters from.
    public static func offscreenFrame(for target: NSRect, reveal: Reveal, screen: NSRect) -> NSRect {
        switch reveal {
        case .slideDown: return target.offsetBy(dx: 0, dy: screen.maxY - target.minY)
        case .slideUp: return target.offsetBy(dx: 0, dy: screen.minY - target.maxY)
        case .slideLeft: return target.offsetBy(dx: screen.minX - target.maxX, dy: 0)
        case .slideRight: return target.offsetBy(dx: screen.maxX - target.minX, dy: 0)
        case .fade, .none: return target
        }
    }

    public func toggle() {
        guard !isAnimating, let window else { return }
        Self.logger.notice("hotkey: appActive=\(NSApplication.shared.isActive) visible=\(window.isVisible) key=\(window.isKeyWindow)")
        if Self.shouldHide(windowVisible: window.isVisible, windowKey: window.isKeyWindow) {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        guard let window else { return }
        isSummoned = true
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        // If Ante was hidden (⌘H) its windows stay ordered out until it unhides — without activating.
        NSApplication.shared.unhideWithoutActivation()
        // Back where it was hidden from, if that is still on a screen; otherwise the configured
        // overlay geometry on the screen with the mouse.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? window.screen ?? NSScreen.main
        if let remembered = summonedFrame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(remembered) }) {
            window.setFrame(remembered, display: false)
        } else if let screen {
            window.setFrame(Self.overlayFrame(in: screen.visibleFrame, width: overlayWidth, height: overlayHeight), display: false)
        }
        // Overlay: on this Space (any Space), above every other window; Ante becomes the active app.
        if restoreBehavior == nil { restoreBehavior = window.collectionBehavior }
        window.collectionBehavior = Self.summonedBehavior
        window.level = Self.summonedLevel   // back to normal once it loses the keyboard
        Self.logger.notice("hotkey: show")
        let target = window.frame
        let screenFrame = window.screen?.frame ?? NSScreen.main?.frame ?? target
        let start = Self.offscreenFrame(for: target, reveal: reveal, screen: screenFrame)
        if reveal == .none {
            Self.orderFrontWithoutActivating(window)
            return
        }
        window.setFrame(start, display: false)
        window.alphaValue = 0
        Self.orderFrontWithoutActivating(window)
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.isAnimating = false }
        })
    }

    /// Front, key, and Ante active — like a Dock click, but without any other window moving.
    private static func orderFrontWithoutActivating(_ window: NSWindow) {
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        guard let window else { return }
        onWillHide?()
        isSummoned = false
        Self.logger.notice("hotkey: hide")
        if window.isVisible { summonedFrame = window.frame }
        guard window.isVisible, reveal != .none, !isAnimating else {
            window.level = .normal
            window.orderOut(nil)
            putBack(window)
            return
        }
        let target = window.frame
        let screenFrame = window.screen?.frame ?? NSScreen.main?.frame ?? target
        let end = Self.offscreenFrame(for: target, reveal: reveal, screen: screenFrame)
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(end, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                window.level = .normal
                window.orderOut(nil)
                // Put the window back where it was, invisibly, so the next reveal starts from there.
                window.setFrame(target, display: false)
                window.alphaValue = 1
                self?.putBack(window)
                self?.isAnimating = false
            }
        })
    }

    /// After hiding: everyday Space behaviour again, and control back to the app you came from.
    private func putBack(_ window: NSWindow) {
        if let restoreBehavior { window.collectionBehavior = restoreBehavior }
        restoreBehavior = nil
        guard NSApplication.shared.isActive else { return }
        if let previousApp, !previousApp.isTerminated, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        } else {
            NSApplication.shared.hide(nil)
        }
    }

    private func windowDidResignKey() {
        guard isSummoned else { return }
        // Give the new key window a moment to be set: a sheet, the palette or Settings is still
        // Ante and must not hide the workspace; another app's window (key becomes nil) may.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSummoned else { return }
            Self.logger.notice("hotkey: resigned key; keyWindow=\(NSApplication.shared.keyWindow?.title ?? "nil") appActive=\(NSApplication.shared.isActive)")
            guard NSApplication.shared.keyWindow == nil else { return }
            self.isSummoned = false
            self.window?.level = .normal
            if self.hideOnFocusLoss { self.hide() }
        }
    }
}
