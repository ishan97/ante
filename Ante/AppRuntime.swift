// Ante/AppRuntime.swift
import AppKit
import Observation
import os
import AnteCore
import AnteTerm
import AnteUI
import AntePanel
import SwiftUI

/// Process-wide wiring: config (+ watcher), the workspace runtime, and the global hotkey.
@MainActor
@Observable
final class AppRuntime {
    private static let logger = Logger(subsystem: "ante.term", category: "app")

    let paths: AppPaths
    let workspace: WorkspaceRuntime
    /// One model for the Settings window, so pending writes and cached font lists survive the
    /// scene being re-evaluated.
    let settings: SettingsModel
    private let liveShell: LiveShellConfig
    private(set) var hotkey: HotkeyWindowToggler?
    /// Set by the app delegate once the window exists; `[window]` changes resize it live.
    weak var windowController: MainWindowController?
    private var configWatcher: ConfigWatcher?
    private var hookWatcher: HookEventWatcher?
    private let integration: InstalledIntegration?
    private let appVersion: String

    init(paths: AppPaths = .default) {
        self.paths = paths
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        self.appVersion = version

        var integration: InstalledIntegration?
        do {
            integration = try ShellIntegration.install(into: paths.shellIntegrationDirectory, version: version)
        } catch {
            Self.logger.error("shell integration install failed: \(error.localizedDescription, privacy: .public)")
        }
        self.integration = integration

        let configResult = ConfigLoader().load(from: paths.configFile)
        let capturedIntegration = integration
        // The factory reads the config the app is running with (kept current by the watcher), not
        // the file: no parse per spawn, and a half-saved file never launches a shell with defaults.
        let live = LiveShellConfig(shell: configResult.config.shell)
        self.liveShell = live
        self.workspace = WorkspaceRuntime(paths: paths, config: configResult.config) { directory in
            let environment = ProcessInfo.processInfo.environment
            let shellConfig = live.shell
            let shellPath = shellConfig.program.isEmpty ? LoginShell.resolve(environment: environment) : shellConfig.program
            return ShellLaunchBuilder(baseEnvironment: environment,
                                      integration: shellConfig.integration ? capturedIntegration : nil,
                                      appVersion: version)
                .makeLaunch(shellPath: shellPath, arguments: shellConfig.arguments)
        }
        self.settings = SettingsModel(runtime: workspace)
        if case let .failed(_, error) = configResult {
            workspace.configError = error
        }

        configWatcher = ConfigWatcher(paths: paths) { [weak self] result in
            guard let self else { return }
            self.liveShell.shell = result.config.shell
            let windowBefore = self.workspace.config.window
            self.workspace.applyConfig(result.config)
            if result.config.window != windowBefore {
                self.windowController?.apply(windowConfig: result.config.window, animate: true)
            }
            // A new overlay size would be applied by the next summon under a still-filled window.
            if let hotkey = self.hotkey,
               (hotkey.overlayWidth, hotkey.overlayHeight) != (result.config.hotkey.width, result.config.hotkey.height) {
                self.windowController?.collapseIfExpanded()
            }
            if case let .failed(_, error) = result { self.workspace.configError = error } else { self.workspace.configError = nil }
            self.hotkey?.hideOnFocusLoss = result.config.hotkey.hideOnFocusLoss
            self.hotkey?.reveal = Self.reveal(for: result.config.hotkey.animation)
            self.hotkey?.overlayWidth = result.config.hotkey.width
            self.hotkey?.overlayHeight = result.config.hotkey.height
        }
        configWatcher?.start()

        hookWatcher = HookEventWatcher(file: paths.claudeHookEventFile) { [weak self] events in
            self?.workspace.board.ingest(events)
        }
        hookWatcher?.start()
        workspace.board.start()
    }

    func installHotkey(window: NSWindow) {
        guard hotkey == nil else { return }
        let toggler = HotkeyWindowToggler(window: window, hideOnFocusLoss: workspace.config.hotkey.hideOnFocusLoss,
                                          reveal: Self.reveal(for: workspace.config.hotkey.animation))
        toggler.overlayWidth = workspace.config.hotkey.width
        toggler.overlayHeight = workspace.config.hotkey.height
        toggler.installGlobalShortcut()
        hotkey = toggler
    }

    private static func reveal(for animation: AnteConfig.Hotkey.Animation) -> HotkeyWindowToggler.Reveal {
        HotkeyWindowToggler.Reveal(rawValue: String(describing: animation)) ?? .slideDown
    }

    func prepareForQuit() {
        configWatcher?.stop()
        hookWatcher?.stop()
        workspace.prepareForQuit()
    }
}

/// The `[shell]` section the launch factory reads; updated whenever the config reloads.
@MainActor
final class LiveShellConfig {
    var shell: AnteConfig.Shell
    init(shell: AnteConfig.Shell) { self.shell = shell }
}
