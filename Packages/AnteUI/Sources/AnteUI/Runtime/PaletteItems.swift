// Packages/AnteUI/Sources/AnteUI/Runtime/PaletteItems.swift
import AppKit
import Foundation
import AnteCore

public struct PaletteItem: Identifiable, Sendable {
    public enum Kind: Sendable { case session, project, action, theme, directory }
    public let id: String
    public let title: String
    public let subtitle: String?
    public let kind: Kind
    public let action: @MainActor @Sendable () -> Void

    var searchText: String { subtitle.map { "\(title) \($0)" } ?? title }
}

@MainActor
public enum PaletteItems {
    public static func build(runtime: WorkspaceRuntime, toggleWindow: @escaping @MainActor @Sendable () -> Void) -> [PaletteItem] {
        var items: [PaletteItem] = []
        for session in runtime.store.allVisibleSessions {
            let project = runtime.store.state.projects.first { $0.id == session.projectID }
            items.append(PaletteItem(id: "session-\(session.id.rawValue)", title: session.name,
                                     subtitle: project?.name, kind: .session) { runtime.open(session: session.id) })
        }
        for project in runtime.store.state.orderedProjects {
            items.append(PaletteItem(id: "project-\(project.id.rawValue)", title: "New Session in \(project.name)",
                                     subtitle: project.rootDirectory.path, kind: .project) { runtime.newSession(in: project.id) })
        }
        let actions: [(String, String, @MainActor @Sendable () -> Void)] = [
            ("split-right", "Split Right", { runtime.splitFocusedPane(axis: .horizontal) }),
            ("split-down", "Split Down", { runtime.splitFocusedPane(axis: .vertical) }),
            ("split-left", "Split Left", { runtime.splitFocusedPane(axis: .horizontal, before: true) }),
            ("split-up", "Split Up", { runtime.splitFocusedPane(axis: .vertical, before: true) }),
            ("close-pane", "Close Pane", { runtime.closeFocusedPane() }),
            ("clear-pane", "Clear Pane", { runtime.clearFocusedPane() }),
            ("toggle-sidebar", "Toggle Sidebar", { runtime.isSidebarVisible.toggle() }),
            ("show-hide", "Hide Ante (Hotkey)", toggleWindow),
            ("find", "Find in Scrollback", { runtime.isSearchVisible = true }),
            ("insert-file", "Insert File Path…", { runtime.insertFilePaths() }),
            ("scratchpad", "To-do & Notes", { runtime.isScratchpadVisible.toggle() }),
            ("pomodoro", "Focus Timer", { runtime.isPomodoroVisible.toggle() }),
            ("pomodoro-toggle", "Start / Pause Focus Timer", { runtime.pomodoro.toggle() }),
            ("toggle-appearance", "Switch Light / Dark", { runtime.toggleAppearance() }),
            ("sessions", "Sessions", { runtime.isSessionsViewerVisible = true }),
            ("prev-prompt", "Jump to Previous Command", { runtime.focusedController?.jumpToPrompt(direction: .previous) }),
            ("next-prompt", "Jump to Next Command", { runtime.focusedController?.jumpToPrompt(direction: .next) }),
            ("select-output", "Select Last Command Output", { runtime.focusedController?.selectPreviousCommandOutput() }),
            ("settings", "Open Settings", { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }),
        ]
        for (id, title, action) in actions {
            items.append(PaletteItem(id: "action-\(id)", title: title, subtitle: nil, kind: .action, action: action))
        }
        for name in runtime.availableThemeNames {
            items.append(PaletteItem(id: "theme-\(name)", title: "Theme: \(name)", subtitle: nil, kind: .theme) { runtime.setThemeName(name) })
        }
        for directory in runtime.recentDirectories.prefix(12) {
            let display = directory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            items.append(PaletteItem(id: "dir-\(directory.path)", title: display, subtitle: "New session here", kind: .directory) {
                if let project = runtime.store.orderedProjectContaining(directory) ?? runtime.store.state.orderedProjects.first {
                    let session = runtime.store.addSession(in: project.id, workingDirectory: directory)
                    runtime.open(session: session.id)
                }
            })
        }
        return items
    }
}
