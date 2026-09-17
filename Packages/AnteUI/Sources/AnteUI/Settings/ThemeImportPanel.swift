// Packages/AnteUI/Sources/AnteUI/Settings/ThemeImportPanel.swift
import AppKit
import UniformTypeIdentifiers

@MainActor
enum ThemeImportPanel {
    static func run(model: SettingsModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .data, UTType(filenameExtension: "toml") ?? .data]
        panel.message = "Choose an iTerm2 .itermcolors or an Alacritty / Ante .toml theme"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importTheme(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not import theme"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }
}
