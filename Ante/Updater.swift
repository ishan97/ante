// Ante/Updater.swift
import AppKit
import Sparkle
import AnteUI

/// Sparkle behind the `UpdateChecking` protocol. One instance for the app's lifetime; Sparkle
/// reads SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks from Info.plist and keeps its own
/// preferences (last check, skipped version, the automatic switch) in UserDefaults.
@MainActor
final class Updater: UpdateChecking {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkNow() { controller.checkForUpdates(nil) }
}
