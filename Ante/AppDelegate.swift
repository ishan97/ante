// Ante/AppDelegate.swift
import AppKit
import UserNotifications
import AnteCore
import AnteUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var runtime: AppRuntime?
    private(set) var window: MainWindowController?
    private var updater: Updater?
    private var keyObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
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
        keepSecondaryWindowsAboveTheWorkspace()
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

    // MARK: Window ordering

    /// The workspace panel sits at a raised level while the hotkey has it summoned, so a window
    /// opened at the normal level — Settings, an alert — would land behind it. Any other Ante
    /// window that becomes key is lifted to the panel's level and ordered in front; it goes back
    /// to the normal level when it closes so it never floats over other apps on its own.
    private func keepSecondaryWindowsAboveTheWorkspace() {
        // Delivered on the main queue, so the main-actor state is safe to touch directly.
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let other = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let other, let panel = self.window?.panel, other !== panel,
                      other.level.rawValue < panel.level.rawValue else { return }
                other.level = panel.level
                other.orderFrontRegardless()
            }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let other = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let other, other !== self.window?.panel else { return }
                other.level = .normal
            }
        }
    }

    // MARK: Notifications

    /// Show the banner even while Ante is active: the board already skips the pane being looked at.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Clicking a "waiting for you" notification opens that session.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info[WaitingNotifier.userInfoSessionKey] as? String, let uuid = UUID(uuidString: raw) else { return }
        await MainActor.run {
            guard let runtime else { return }
            let id = SessionID(rawValue: uuid)
            if runtime.workspace.store.state.sessions.contains(where: { $0.id == id }) {
                runtime.workspace.open(session: id)
            }
            window?.show()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // closing the window only hides it; ⌘Q quits
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runtime?.prepareForQuit()
        return .terminateNow
    }
}
