// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Overlays.swift
import AppKit
import SwiftUI
import AnteCore
import AnteTerm
import AnteTheme

extension WorkspaceRuntime {
    /// The chrome accent from `[theme] accent`, or Ante's amber.
    public var accentColor: Color { AnteAccent.color(for: config.theme.accent) }
    /// Window background and opacity from `[theme] background` / `opacity`. Without a custom
    /// background the chrome takes the terminal theme's own, so toolbar, margins and terminal
    /// read as one surface.
    public var chrome: AnteChrome {
        let themeBackground = appearance.theme.background
        let base = config.theme.background.flatMap(HexColor.parse)
            ?? HexColor(red: Double(themeBackground.red) / 255, green: Double(themeBackground.green) / 255, blue: Double(themeBackground.blue) / 255)
        return AnteChrome(background: base, opacity: config.theme.opacity, blur: config.theme.blur,
                          header: config.theme.header.flatMap(HexColor.parse))
    }

    public var focusedController: TerminalSessionController? {
        guard let pane = focusedPaneID else { return nil }
        return controller(for: pane)
    }

    /// Distinct working directories across live sessions, most recently focused first.
    public var recentDirectories: [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for session in store.allVisibleSessions {
            let url = existingLayout(for: session.id)?.paneIDs.first.flatMap { controller(for: $0).currentDirectory } ?? session.workingDirectory
            if seen.insert(url.path).inserted { out.append(url) }
        }
        return out
    }

    /// Persists a theme choice through config.toml; the watcher applies it.
    public func setThemeName(_ name: String) {
        do {
            try ConfigEditor(paths: paths).write(section: "theme", key: "name", value: .string(name))
        } catch {
            configError = ConfigError(line: nil, message: "could not write theme: \(error)")
        }
    }

    /// Whether the chrome is currently dark (a custom background decides by its luminance).
    public var isDarkAppearance: Bool { appearance.theme.appearance == .dark }

    /// A custom window background decides light or dark by its own luminance; switching clears it
    /// so the theme's own background can show.
    public var hasCustomBackground: Bool { config.theme.background != nil }

    /// Flips `[theme] appearance` between light and dark. Ante's own themes swap with it
    /// (ante-dark ⇄ ante-light); another named theme keeps its palette and only the chrome follows.
    public func toggleAppearance() {
        let next: AnteConfig.Appearance = isDarkAppearance ? .light : .dark
        let editor = ConfigEditor(paths: paths)
        do {
            if hasCustomBackground { try editor.write(section: "theme", key: "background", value: .string("")) }
            try editor.write(section: "theme", key: "appearance", value: .string(next.rawValue))
            switch config.theme.name {
            case "ante-dark" where next == .light: try editor.write(section: "theme", key: "name", value: .string("ante-light"))
            case "ante-light" where next == .dark: try editor.write(section: "theme", key: "name", value: .string("ante-dark"))
            default: break
            }
        } catch {
            configError = ConfigError(line: nil, message: "could not write appearance: \(error)")
        }
    }

    public var availableThemeNames: [String] {
        ThemeLoader(userDirectory: paths.themesDirectory).availableNames
    }

    /// ⌘K by default: clears the focused pane's screen and scrollback.
    public func clearFocusedPane() {
        focusedController?.clearScreen()
    }

    public func openLink(_ match: LinkDetector.Match) {
        LinkOpener.perform(LinkOpener.plan(for: match))
    }
}
