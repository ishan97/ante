// Packages/AnteUI/Sources/AnteUI/Settings/SettingsModel.swift
import AppKit
import SwiftUI
import Observation
import AnteCore
import AnteTheme

/// Settings is a thin editor over config.toml. Every setter writes one key; the file watcher
/// applies it to the running app, so Settings and a text editor are interchangeable.
@MainActor
@Observable
public final class SettingsModel {
    public private(set) var lastError: String?
    private let runtime: WorkspaceRuntime
    private let editor: ConfigEditor
    /// Values the user just set, shown immediately while the file write is coalesced.
    private var pending: [String: ConfigEditor.Value] = [:]
    private var flushTask: Task<Void, Never>?

    public init(runtime: WorkspaceRuntime) {
        self.runtime = runtime
        self.editor = ConfigEditor(paths: runtime.paths)
    }

    private var config: AnteConfig { runtime.config }

    /// Records the value for instant display and writes it ~80 ms after the last change, so a
    /// slider drag costs one file write, not hundreds.
    private func write(_ section: String, _ key: String, _ value: ConfigEditor.Value) {
        pending["\(section).\(key)"] = value
        flushTask?.cancel()
        flushTask = Task { [self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            flushTask = nil   // so the overlay cleanup below knows no newer write is pending
            flush()
        }
    }

    /// Writes every coalesced change now. Called on window close and by tests.
    public func flushPendingWrites() {
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    private func flush() {
        let batch = pending
        for (path, value) in batch {
            let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
            do {
                try editor.write(section: parts[0], key: parts[1], value: value)
                lastError = nil
            } catch {
                lastError = String(describing: error)
                pending[path] = nil
            }
        }
        // The watcher hands the runtime the new config within ~150 ms; keep the overlay until
        // then so a released slider doesn't snap back to the old value for a frame.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.flushTask == nil else { return }
            for (path, value) in batch where self.pending[path] == value { self.pending[path] = nil }
        }
    }

    private func pendingDouble(_ path: String) -> Double? {
        if case let .double(v)? = pending[path] { return v }
        return nil
    }
    private func pendingBool(_ path: String) -> Bool? {
        if case let .bool(v)? = pending[path] { return v }
        return nil
    }
    private func pendingString(_ path: String) -> String? {
        if case let .string(v)? = pending[path] { return v }
        return nil
    }

    public var fontFamily: String {
        get { config.font.family }
        set { write("font", "family", .string(newValue)) }
    }
    public var fontSize: Double {
        get { pendingDouble("font.size") ?? config.font.size }
        set { write("font", "size", .double(min(max(newValue, 8), 40))) }
    }
    public var ligatures: Bool {
        get { config.font.ligatures }
        set { write("font", "ligatures", .bool(newValue)) }
    }
    public var cursorStyle: AnteConfig.Cursor.Style {
        get { config.cursor.style }
        set { write("cursor", "style", .string(newValue.rawValue)) }
    }
    public var cursorBlink: Bool {
        get { config.cursor.blink }
        set { write("cursor", "blink", .bool(newValue)) }
    }
    public var themeName: String {
        get { config.theme.name }
        set { write("theme", "name", .string(newValue)) }
    }
    public var accentHex: String {
        get { pendingString("theme.accent") ?? config.theme.accent ?? AnteStyle.defaultAccentHex }
        set { if let hex = HexColor.parse(newValue)?.hex { write("theme", "accent", .string(hex)) } }
    }
    public var accentColor: Color {
        get { AnteAccent.color(for: accentHex) }
        set { if let hex = AnteAccent.hex(for: newValue) { accentHex = hex } }
    }
    public var isDefaultAccent: Bool { accentHex == AnteStyle.defaultAccentHex }

    /// nil = the theme's own background.
    public var backgroundHex: String? {
        get {
            if let pending = pendingString("theme.background") { return pending.isEmpty ? nil : pending }
            return config.theme.background
        }
        set { write("theme", "background", .string(newValue.flatMap { HexColor.parse($0)?.hex } ?? "")) }
    }
    public var backgroundColor: Color {
        get {
            if let hex = backgroundHex, let c = HexColor.parse(hex) { return Color(.sRGB, red: c.red, green: c.green, blue: c.blue) }
            let bg = runtime.appearance.theme.background
            return Color(.sRGB, red: Double(bg.red) / 255, green: Double(bg.green) / 255, blue: Double(bg.blue) / 255)
        }
        set { if let hex = AnteAccent.hex(for: newValue) { backgroundHex = hex } }
    }
    public var hasCustomBackground: Bool { backgroundHex != nil }

    /// nil = the header follows the window.
    public var headerHex: String? {
        get {
            if let pending = pendingString("theme.header") { return pending.isEmpty ? nil : pending }
            return config.theme.header
        }
        set { write("theme", "header", .string(newValue.flatMap { HexColor.parse($0)?.hex } ?? "")) }
    }
    public var headerColor: Color {
        get {
            if let hex = headerHex, let c = HexColor.parse(hex) { return Color(.sRGB, red: c.red, green: c.green, blue: c.blue) }
            return backgroundColor
        }
        set { if let hex = AnteAccent.hex(for: newValue) { headerHex = hex } }
    }
    public var hasCustomHeader: Bool { headerHex != nil }
    public var windowBlur: Double {
        get { pendingDouble("theme.blur") ?? config.theme.blur }
        set { write("theme", "blur", .double((newValue * 100).rounded() / 100)) }
    }
    public var windowOpacity: Double {
        get { pendingDouble("theme.opacity") ?? config.theme.opacity }
        set { write("theme", "opacity", .double((newValue * 100).rounded() / 100)) }
    }
    public var appearance: AnteConfig.Appearance {
        get { config.theme.appearance }
        set { write("theme", "appearance", .string(newValue.rawValue)) }
    }
    public var wallpaperPath: String {
        get { pendingString("wallpaper.path") ?? config.wallpaper.path }
        set { write("wallpaper", "path", .string(newValue)) }
    }
    public var wallpaperOpacity: Double {
        get { pendingDouble("wallpaper.opacity") ?? config.wallpaper.opacity }
        set { write("wallpaper", "opacity", .double((newValue * 100).rounded() / 100)) }
    }
    public var wallpaperBlur: Double {
        get { pendingDouble("wallpaper.blur") ?? config.wallpaper.blur }
        set { write("wallpaper", "blur", .double(newValue.rounded())) }
    }
    public var hotkeyAnimation: AnteConfig.Hotkey.Animation {
        get { pendingString("hotkey.animation").flatMap(AnteConfig.Hotkey.Animation.init(rawValue:)) ?? config.hotkey.animation }
        set { write("hotkey", "animation", .string(newValue.rawValue)) }
    }
    public var hotkeyWidth: Double {
        get { pendingDouble("hotkey.width") ?? config.hotkey.width }
        set { write("hotkey", "width", .double((newValue * 100).rounded() / 100)) }
    }
    public var hotkeyHeight: Double {
        get { pendingDouble("hotkey.height") ?? config.hotkey.height }
        set { write("hotkey", "height", .double((newValue * 100).rounded() / 100)) }
    }
    public var hideOnFocusLoss: Bool {
        get { config.hotkey.hideOnFocusLoss }
        set { write("hotkey", "hide_on_focus_loss", .bool(newValue)) }
    }
    public var shellProgram: String {
        get { config.shell.program }
        set { write("shell", "program", .string(newValue)) }
    }
    public var shellIntegration: Bool {
        get { config.shell.integration }
        set { write("shell", "integration", .bool(newValue)) }
    }
    public var confirmMultilinePaste: Bool {
        get { config.security.confirmMultilinePaste }
        set { write("security", "confirm_multiline_paste", .bool(newValue)) }
    }

    public var keyBindings: [(key: String, label: String, binding: KeyBinding)] { config.keys.all }

    // MARK: Agents

    public var quietSeconds: Double {
        get { pendingDouble("agents.quiet_seconds") ?? config.agents.quietSeconds }
        set { write("agents", "quiet_seconds", .double(newValue.rounded())) }
    }

    private var claudeHookInstaller: ClaudeHookInstaller { ClaudeHookInstaller(eventFile: runtime.paths.claudeHookEventFile) }
    public var claudeSettingsPath: String { claudeHookInstaller.settingsFile.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }

    private var cachedRetention: (revision: Int, value: Int)?
    /// Claude Code's `cleanupPeriodDays`: how long its transcripts (and so Ante's history) survive.
    public var claudeRetentionDays: Int {
        get {
            if let cached = cachedRetention, cached.revision == hookRevision { return cached.value }
            let value = claudeHookInstaller.retentionDays()
            cachedRetention = (hookRevision, value)
            return value
        }
        set {
            do {
                try claudeHookInstaller.setRetentionDays(newValue == ClaudeHookInstaller.defaultRetentionDays ? nil : newValue)
                lastError = nil
            } catch {
                lastError = String(describing: error)
            }
            hookRevision += 1
        }
    }
    public static let retentionChoices: [(label: String, days: Int)] = [("30 days", 30), ("90 days", 90), ("180 days", 180), ("1 year", 365), ("10 years", 3650)]

    private var cachedHookInstalled: (revision: Int, value: Bool)?
    public var claudeHookInstalled: Bool {
        get {
            if let cached = cachedHookInstalled, cached.revision == hookRevision { return cached.value }
            let value = claudeHookInstaller.isInstalled()
            cachedHookInstalled = (hookRevision, value)
            return value
        }
        set {
            do {
                if newValue { try claudeHookInstaller.install() } else { try claudeHookInstaller.uninstall() }
                lastError = nil
            } catch {
                lastError = "hook: \(error)"
            }
            hookRevision &+= 1
        }
    }
    /// Bumped after install/uninstall so the toggle re-reads the file.
    public private(set) var hookRevision = 0

    public func clearAnteHistory() {
        AnteSessionHistoryStore(paths: runtime.paths).clear()
    }

    /// Validates and writes one shortcut. Returns an error message for the field to show, or nil.
    @discardableResult
    public func setKeyBinding(_ configKey: String, text: String) -> String? {
        do {
            let binding = try KeyBinding.parse(text)
            if let clash = config.keys.all.first(where: { $0.key != configKey && $0.binding == binding }) {
                return "already used by \(clash.label)"
            }
            write("keys", configKey, .string(binding.text))
            return nil
        } catch let error as KeyBinding.ParseError {
            return error.message
        } catch {
            return String(describing: error)
        }
    }

    private var cachedMonospaceFamilies: [String]?
    /// Enumerating every installed font costs hundreds of milliseconds; do it once per model.
    public var monospaceFamilies: [String] {
        if let cached = cachedMonospaceFamilies { return cached }
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family), let first = members.first,
                  let name = first[0] as? String, let font = NSFont(name: name, size: 12) else { return false }
            return font.isFixedPitch
        }
        let result = Array(Set(families + [config.font.family, "JetBrains Mono"])).sorted()
        cachedMonospaceFamilies = result
        return result
    }

    public var themeNames: [String] { runtime.availableThemeNames }

    /// Imports an `.itermcolors` or Alacritty/Ante `.toml` into the user themes directory and returns its name.
    @discardableResult
    public func importTheme(from url: URL) throws -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let rawSlug = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let slug = rawSlug.isEmpty ? "imported" : rawSlug
        let theme: TerminalTheme
        switch url.pathExtension.lowercased() {
        case "itermcolors":
            theme = try ITermColorsImporter.import(plistData: try Data(contentsOf: url), name: name)
        case "toml":
            let text = try String(contentsOf: url, encoding: .utf8)
            if let parsed = try? TerminalTheme.parse(toml: text) {
                theme = parsed
            } else {
                theme = try AlacrittyImporter.import(toml: text, name: name)
            }
        default:
            throw ConfigError(line: nil, message: "unsupported theme file: \(url.lastPathComponent)")
        }
        try FileManager.default.createDirectory(at: runtime.paths.themesDirectory, withIntermediateDirectories: true)
        try AtomicFile.write(Data(theme.toml.utf8), to: runtime.paths.themesDirectory.appendingPathComponent("\(slug).toml"))
        themeName = slug
        return slug
    }

}
