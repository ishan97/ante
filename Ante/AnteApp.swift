// Ante/AnteApp.swift
import SwiftUI
import AnteTerm
import AnteUI

@main
struct AnteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let runtime = AppRuntime()

    init() {
        // The workspace window is AppKit (see MainWindow.swift); the delegate opens it at launch.
        appDelegate.runtime = runtime
    }

    var body: some Scene {
        Settings {
            SettingsView(model: runtime.settings,
                         prefersDark: runtime.workspace.appearance.theme.appearance == .dark)
        }
        .commands {
            SessionCommands(runtime: runtime.workspace, toggleWindow: { runtime.hotkey?.toggle() })
            EditCommands(runtime: runtime.workspace)
            AppCommands(runtime: runtime.workspace)
            ViewCommands(runtime: runtime.workspace, settings: runtime.settings,
                         toggleFullScreen: { [appDelegate] in appDelegate.window?.toggleFullScreen() })
        }
    }
}

/// View menu: iTerm-style full screen and text size, all rebindable under `[keys]`.
struct ViewCommands: Commands {
    let runtime: WorkspaceRuntime
    let settings: SettingsModel
    let toggleFullScreen: () -> Void

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Full Screen") { toggleFullScreen() }
                .keyboardShortcut(runtime.config.keys.toggleFullscreen.shortcut)
            Divider()
            Button("Bigger Text") { settings.stepFontSize(by: 1) }
                .keyboardShortcut(runtime.config.keys.fontBigger.shortcut)
            Button("Smaller Text") { settings.stepFontSize(by: -1) }
                .keyboardShortcut(runtime.config.keys.fontSmaller.shortcut)
            Button("Actual Text Size") { settings.resetFontSize() }
                .keyboardShortcut(runtime.config.keys.fontReset.shortcut)
        }
    }
}

/// "Check for Updates…" under About, the way every Sparkle app does it.
struct AppCommands: Commands {
    let runtime: WorkspaceRuntime

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { runtime.updater?.checkNow() }
                .disabled(!(runtime.updater?.canCheck ?? false))
        }
    }
}

/// Find, palette, and command navigation live in Edit, next to copy/paste.
struct EditCommands: Commands {
    let runtime: WorkspaceRuntime

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { runtime.isSearchVisible = true }
                .keyboardShortcut(runtime.config.keys.find.shortcut)
            Button("Command Palette") { runtime.isPaletteVisible = true }
                .keyboardShortcut(runtime.config.keys.commandPalette.shortcut)
            Button("Insert File Path…") { runtime.insertFilePaths() }
                .keyboardShortcut(runtime.config.keys.insertFile.shortcut)
            Divider()
            Button("Previous Command") { runtime.focusedController?.jumpToPrompt(direction: .previous) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Next Command") { runtime.focusedController?.jumpToPrompt(direction: .next) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Select Last Command Output") { runtime.focusedController?.selectPreviousCommandOutput() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}

/// Menu bar + shortcuts. Every action goes through the runtime so the sidebar stays in sync.
struct SessionCommands: Commands {
    let runtime: WorkspaceRuntime
    let toggleWindow: () -> Void

    var body: some Commands {
        CommandMenu("Session") {
            Button("Show or Hide Ante (Hotkey)") { toggleWindow() }
            Button("Sessions") { runtime.isSessionsViewerVisible.toggle() }
                .keyboardShortcut(runtime.config.keys.sessionsBoard.shortcut)
            Button("To-do & Notes") { runtime.isScratchpadVisible.toggle() }
                .keyboardShortcut(runtime.config.keys.scratchpad.shortcut)
            Button("Focus Timer") { runtime.isPomodoroVisible.toggle() }
            Divider()

            Button("New Session") {
                if let project = runtime.store.focusedSession.flatMap({ s in runtime.store.state.projects.first { $0.id == s.projectID } })
                    ?? runtime.store.state.orderedProjects.first {
                    runtime.newSession(in: project.id)
                }
            }
            .keyboardShortcut(runtime.config.keys.newSession.shortcut)

            Button("Close Pane") { runtime.closeFocusedPane() }
                .keyboardShortcut(runtime.config.keys.closePane.shortcut)
            Button("Clear Pane") { runtime.clearFocusedPane() }
                .keyboardShortcut(runtime.config.keys.clearPane.shortcut)

            Divider()

            Button("Split Right") { runtime.splitFocusedPane(axis: .horizontal) }
                .keyboardShortcut(runtime.config.keys.splitRight.shortcut)
            Button("Split Down") { runtime.splitFocusedPane(axis: .vertical) }
                .keyboardShortcut(runtime.config.keys.splitDown.shortcut)
            Button("Split Left") { runtime.splitFocusedPane(axis: .horizontal, before: true) }
                .keyboardShortcut(runtime.config.keys.splitLeft.shortcut)
            Button("Split Up") { runtime.splitFocusedPane(axis: .vertical, before: true) }
                .keyboardShortcut(runtime.config.keys.splitUp.shortcut)

            Divider()

            Button("Focus Pane Left") { runtime.focusNeighbor(.left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Focus Pane Right") { runtime.focusNeighbor(.right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Focus Pane Up") { runtime.focusNeighbor(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Focus Pane Down") { runtime.focusNeighbor(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button("Previous Session") { runtime.focusSession(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Session") { runtime.focusSession(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            ForEach(1...9, id: \.self) { n in
                Button("Session \(n)") { runtime.focusSession(index: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: .command)
            }
        }
    }
}
