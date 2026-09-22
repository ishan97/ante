// Ante/MainWindow.swift
import AppKit
import AntePanel
import AnteCore
import SwiftUI
import AnteUI

/// Ante's one workspace window. It is an `NSPanel` with `.nonactivatingPanel` so the hotkey can
/// drop it over whatever you are doing and let you type, without making Ante the active app —
/// the app you came from keeps its menu bar and windows exactly as they were, the way a
/// floating hotkey window should. Launched from the Dock it behaves like any window.
final class MainPanel: NSPanel {
    /// Set by the controller; lets the header band stop where the toolbar's controls start.
    weak var runtime: WorkspaceRuntime?
    override var canBecomeKey: Bool { true }
    /// Main only while Ante is the active app: becoming main from an inactive app would activate
    /// it, which is exactly what the overlay must not do.
    override var canBecomeMain: Bool { NSApp.isActive }

    /// While summoned over another app, Ante is not active, so AppKit never offers ⌘-shortcuts to
    /// its menu bar. Offer them ourselves: ⌘K, ⌘⇧S, ⌘C/⌘V … all keep working in the overlay.
    /// Height of the header band (toolbar and the sidebar strip beside it) that acts as the
    /// title bar. Must match `AnteStyle.toolbarHeight`.
    static let headerHeight: CGFloat = 38
    /// Right-hand toolbar controls keep their clicks; the traffic lights keep theirs on the left.
    static let headerControlsWidth: CGFloat = 200
    static let trafficLightsWidth: CGFloat = 80

    /// The window has no visible title bar and SwiftUI's hosting view claims every click in the
    /// header, so give the header title-bar manners here: drag moves the window, double-click
    /// does what System Settings says a title bar double-click does.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView {
            let p = event.locationInWindow
            let controls = runtime?.headerControlsWidth ?? Self.headerControlsWidth
            let inBand = p.y >= contentView.bounds.height - Self.headerHeight
                && p.x > Self.trafficLightsWidth && p.x < frame.width - controls
            if inBand {
                if event.clickCount == 2 { Self.performTitleBarDoubleClick(on: self) } else { performDrag(with: event) }
                return
            }
        }
        super.sendEvent(event)
    }

    /// Mirrors System Settings › Desktop & Dock › "Double-click a window's title bar to".
    static func performTitleBarDoubleClick(on window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: toggleZoom(window)   // NSWindow.zoom is a no-op on a panel; Maximize and Fill both fill the usable screen
        }
    }

    private static var zoomRestoreFrames: [ObjectIdentifier: NSRect] = [:]
    /// ⌘↩: macOS's own full screen (the window gets its own Space), the way iTerm2's default
    /// works; the next press goes back. While full screen the hotkey hides and unhides the app
    /// instead of moving the window (see HotkeyWindowToggler).
    /// AppKit ignores `toggleFullScreen` for a window of an inactive app (Ante summoned by the
    /// hotkey stays inactive on purpose), and drops it when asked in the same turn as activation.
    /// So: activate, then toggle on the next turn of the run loop.
    static func toggleFullScreen(_ window: NSWindow) {
        if !isFullScreen(window) {
            // The hotkey overlay is a "full-screen auxiliary" window on every Space at a raised
            // level; such a window can never become a full-screen Space of its own. Make it an
            // ordinary primary window again first (the next summon sets the overlay behaviour back).
            window.collectionBehavior = [.managed, .fullScreenPrimary]
            window.level = .normal
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) { window.toggleFullScreen(nil) }
                return
            }
        }
        window.toggleFullScreen(nil)
    }

    static func isFullScreen(_ window: NSWindow) -> Bool { window.styleMask.contains(.fullScreen) }

    /// `NSWindow.zoom` is a no-op on a panel, so do what it would: fill the screen's usable area,
    /// and put the previous frame back on the next double-click.
    static func toggleZoom(_ window: NSWindow) {
        guard let visible = window.screen?.visibleFrame else { return }
        let key = ObjectIdentifier(window)
        if let previous = zoomRestoreFrames[key], window.frame.insetBy(dx: -2, dy: -2).contains(visible) {
            zoomRestoreFrames[key] = nil
            window.setFrame(previous, display: true, animate: true)
        } else {
            zoomRestoreFrames[key] = window.frame
            window.setFrame(visible, display: true, animate: true)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘↩ (or whatever `[keys] toggle_fullscreen` says) is handled here, before the menu: it
        // must work whether Ante is the active app or merely owns the key window.
        if let runtime, runtime.config.keys.toggleFullscreen.matches(event) {
            Self.toggleFullScreen(self)
            return true
        }
        if super.performKeyEquivalent(with: event) { return true }
        guard !NSApp.isActive, let menu = NSApp.mainMenu else { return false }
        return menu.performKeyEquivalent(with: event)
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    let panel: MainPanel

    init(runtime: AppRuntime) {
        panel = MainPanel(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        panel.title = "Ante"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hidesOnDeactivate = false        // NSPanel's default would hide it with the app
        panel.isReleasedWhenClosed = false     // the red button hides; the hotkey or Dock brings it back
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 720, height: 420)
        panel.collectionBehavior = [.managed, .fullScreenPrimary]
        panel.animationBehavior = .none        // the hotkey does its own reveal
        panel.delegate = self
        panel.runtime = runtime.workspace
        let hosting = NSHostingView(rootView: RootView().environment(runtime))
        // Never let SwiftUI's ideal content size drive the window: switching sessions or opening
        // the board would otherwise snap the window back to a default size and place.
        hosting.sizingOptions = []
        panel.contentView = hosting
        // setFrameAutosaveName restores the saved frame itself, so the configured size is applied
        // after it; the remembered frame still decides which screen and corner the window keeps.
        if !panel.setFrameUsingName("AnteMainWindow") { panel.center() }
        panel.setFrameAutosaveName("AnteMainWindow")
        apply(windowConfig: runtime.workspace.config.window, animate: false)
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    /// `[window] width/height` as fractions of the screen, anchored to the top-left of the usable
    /// area on the screen the window is on; 0 leaves the remembered frame alone. A full-screen
    /// window is left alone too: the new size applies once it leaves full screen.
    func apply(windowConfig: AnteConfig.Window, animate: Bool) {
        guard windowConfig.isFixed, !MainPanel.isFullScreen(panel),
              let visible = Self.screen(showing: panel.frame)?.visibleFrame else { return }
        let frame = WindowSizing.frame(fraction: windowConfig.width, windowConfig.height, in: visible, minSize: panel.minSize)
        if frame != panel.frame { panel.setFrame(frame, display: true, animate: animate) }
    }

    func toggleFullScreen() { MainPanel.toggleFullScreen(panel) }

    /// The full-screen transition can drop key status; claim it back so ⌘↩ and typing work.
    func windowDidEnterFullScreen(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The screen that shows most of `frame`. `NSWindow.screen` is nil before the window is
    /// ordered in, and `NSScreen.main` is whichever display has the keyboard, which is the wrong
    /// one to size against when the remembered frame lives on the other display.
    static func screen(showing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? NSScreen.main
    }
}

private extension NSRect {
    /// Zero for null and empty rects, so a screen that does not touch the frame never wins.
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
