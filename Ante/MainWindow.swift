// Ante/MainWindow.swift
import AppKit
import AntePanel
import AnteCore
import SwiftUI
import AnteUI

/// Ante's one workspace window. The hotkey floats it over whatever you are doing and makes Ante
/// the active app (`HotkeyWindowToggler`); otherwise it is an ordinary window.
///
/// It is not a `.nonactivatingPanel`. macOS never activates the app behind such a panel, so
/// chosen any way but the hotkey (a click, Mission Control) it came forward and then fell back
/// behind the app that stayed active. What that mode was for, dropping in over another app's
/// full-screen window, stopped working when the hotkey began activating Ante (c8328b6): macOS
/// switches Spaces for an app that activates there, whatever the window.
final class MainPanel: NSPanel {
    /// Set by the controller; lets the header band stop where the toolbar's controls start.
    weak var runtime: WorkspaceRuntime?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
            if inBand, !isExpanded {   // a filled window is neither dragged nor zoomed from its header
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
    /// Fill screen: the frame to go back to while expanded.
    var expandedRestoreFrame: NSRect?
    var isExpanded: Bool { expandedRestoreFrame != nil }

    /// ⌘↩: the window covers the whole screen and the menu bar and Dock slide away while Ante is
    /// in front; the next press restores the frame. The hotkey leaves this state alone (it hides
    /// and shows the window as it is); closing or quitting ends it.
    func toggleExpanded(animate: Bool = true) {
        if let previous = expandedRestoreFrame {
            expandedRestoreFrame = nil
            NSApp.presentationOptions = []
            setFrame(previous, display: true, animate: animate)
        } else if let screen = screen ?? NSScreen.main {
            expandedRestoreFrame = frame
            // The menu bar and Dock only auto-hide for the active app: make sure that is Ante.
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
            setFrame(screen.frame, display: true, animate: animate)
        }
    }

    /// AppKit keeps a window below the menu bar; while expanded the frame is the whole screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isExpanded ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    func collapseIfExpanded(animate: Bool = true) { if isExpanded { toggleExpanded(animate: animate) } }

    /// The green button. `NSWindow.zoom` is a no-op on a panel, so do the zoom by hand.
    override func zoom(_ sender: Any?) { if !isExpanded { Self.toggleZoom(self) } }

    /// A screen-sized frame is not worth remembering: a crash while filled would otherwise
    /// relaunch screen-sized.
    override func saveFrame(usingName name: NSWindow.FrameAutosaveName) {
        if !isExpanded { super.saveFrame(usingName: name) }
    }

    /// ⌘↩: fill the screen in place (see `toggleExpanded`). macOS's own full screen is off for
    /// this window (`.fullScreenNone`): a separate Space and the hotkey overlay never agreed.
    static func toggleFullScreen(_ window: NSWindow) { (window as? MainPanel)?.toggleExpanded() }

    static func isFullScreen(_ window: NSWindow) -> Bool { (window as? MainPanel)?.isExpanded == true }

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
        if let runtime, runtime.config.keys.toggleFullscreen.matches(event) {   // auto-repeat is refused inside matches
            Self.toggleFullScreen(self)
            return true
        }
        if super.performKeyEquivalent(with: event) { return true }
        // Should the window have the keyboard while another app is active (a moment around
        // activation), still offer ⌘-shortcuts to Ante's own menu bar.
        guard !NSApp.isActive, let menu = NSApp.mainMenu else { return false }
        return menu.performKeyEquivalent(with: event)
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    let panel: MainPanel

    init(runtime: AppRuntime) {
        panel = MainPanel(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        panel.title = "Ante"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hidesOnDeactivate = false        // NSPanel's default would hide it with the app
        panel.isReleasedWhenClosed = false     // the red button hides; the hotkey or Dock brings it back
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 720, height: 420)
        panel.collectionBehavior = [.managed, .fullScreenNone]
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
    /// area on the screen the window is on; 0 leaves the remembered frame alone. A filled window
    /// is left alone too (a size change made while filled is not applied; the next launch uses it).
    func apply(windowConfig: AnteConfig.Window, animate: Bool) {
        guard windowConfig.isFixed, !MainPanel.isFullScreen(panel),
              let visible = Self.screen(showing: panel.frame)?.visibleFrame else { return }
        let frame = WindowSizing.frame(fraction: windowConfig.width, windowConfig.height, in: visible, minSize: panel.minSize)
        if frame != panel.frame { panel.setFrame(frame, display: true, animate: animate) }
    }

    func toggleFullScreen() { MainPanel.toggleFullScreen(panel) }

    /// The expanded state is not something to carry into a closed window or the next launch;
    /// no animation on the way out, the window is going away anyway.
    func collapseIfExpanded() { panel.collapseIfExpanded(animate: false) }
    func windowWillClose(_ notification: Notification) { collapseIfExpanded() }
    func windowWillMiniaturize(_ notification: Notification) { collapseIfExpanded() }

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
