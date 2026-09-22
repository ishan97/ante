// Ante/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var runtime: AppRuntime?
    private(set) var window: MainWindowController?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard let runtime else { return }
        let controller = MainWindowController(runtime: runtime)
        window = controller
        runtime.windowController = controller
        controller.show()
        runtime.installHotkey(window: controller.panel)
        // Sparkle reads SUFeedURL / SUPublicEDKey from Info.plist; a Debug build from Xcode has
        // both, so the updater works in development against the live feed.
        let updater = Updater()
        runtime.workspace.updater = updater
        self.updater = updater
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dock click with the window closed or hidden: bring it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.show() }
        return true
    }

    /// Any activation with nothing showing (Dock, ⌘-Tab, AppleScript) brings the window back.
    func applicationDidBecomeActive(_ notification: Notification) {
        if let window, !window.panel.isVisible { window.show() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // closing the window only hides it; ⌘Q quits
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runtime?.prepareForQuit()
        return .terminateNow
    }
}
