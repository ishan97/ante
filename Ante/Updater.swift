// Ante/Updater.swift
import AppKit
import Combine
import Observation
import Sparkle
import AnteUI

/// Sparkle behind the `UpdateChecking` protocol. One instance for the app's lifetime; Sparkle
/// reads SUFeedURL / SUPublicEDKey / SUEnableAutomaticChecks from Info.plist and keeps its own
/// preferences (last check, skipped version, the automatic switch) in UserDefaults.
@MainActor
@Observable
final class Updater: NSObject, UpdateChecking, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: AnyCancellable?
    /// Mirrors Sparkle's `canCheckForUpdates`, so the menu item and the Settings button really
    /// disable while a check or an install is in progress.
    private(set) var canCheck = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheck = value }
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkNow() { controller.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    /// A development build carries build number 1, so every published release would look newer
    /// and Sparkle would offer to replace the app in DerivedData. Scheduled checks are refused
    /// here rather than by flipping the preference, which Debug and Release share through the
    /// bundle identifier. Manual "Check for Updates…" still works for testing.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        #if DEBUG
        if updateCheck == .updatesInBackground {
            throw NSError(domain: "ante.term", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scheduled update checks are off in development builds."])
        }
        #endif
    }
}
