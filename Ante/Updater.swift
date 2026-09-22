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
final class Updater: UpdateChecking {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: AnyCancellable?
    /// Mirrors Sparkle's `canCheckForUpdates`, so the menu item and the Settings button really
    /// disable while a check or an install is in progress.
    private(set) var canCheck = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #if DEBUG
        // A development build carries build number 1, so every published release would look newer
        // and Sparkle would offer to replace the app in DerivedData. Manual checks still work.
        controller.updater.automaticallyChecksForUpdates = false
        #endif
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheck = value }
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkNow() { controller.checkForUpdates(nil) }
}
