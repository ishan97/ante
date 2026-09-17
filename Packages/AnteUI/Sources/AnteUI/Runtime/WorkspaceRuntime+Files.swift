// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Files.swift
import AppKit
import AnteCore

extension WorkspaceRuntime {
    /// Lets the user pick files or folders and types their quoted paths into the focused pane —
    /// the keyboard-friendly twin of dragging files onto the terminal.
    public func insertFilePaths() {
        guard let controller = focusedController else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        panel.message = "Insert the selected paths at the cursor"
        panel.directoryURL = controller.currentDirectory
        guard let window = controller.view.window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            controller.view.insertPaths(panel.urls)
        }
    }
}
