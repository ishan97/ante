// Packages/AnteUI/Sources/AnteUI/Settings/SettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import AntePanel
import AnteCore

public struct SettingsView: View {
    @Bindable var model: SettingsModel
    /// Follows the terminal theme like the main window does.
    var prefersDark: Bool

    public init(model: SettingsModel, prefersDark: Bool) {
        self.model = model
        self.prefersDark = prefersDark
    }

    public var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintpalette") }
            shell.tabItem { Label("Shell", systemImage: "terminal") }
            keys.tabItem { Label("Keys", systemImage: "keyboard") }
            agents.tabItem { Label("Agents", systemImage: "rectangle.3.group") }
            privacy.tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 520, height: 400)
        .preferredColorScheme(prefersDark ? .dark : .light)
        .onDisappear { model.flushPendingWrites() }
        .environment(\.anteAccent, model.accentColor)
        .overlay(alignment: .bottom) {
            if let error = model.lastError {
                Text(error).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusFailed).padding(8)
            }
        }
    }

    private var general: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $model.fontFamily) {
                    ForEach(model.monospaceFamilies, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("Size")
                    Slider(value: $model.fontSize, in: 9...24, step: 0.5)
                    Text(String(format: "%.1f pt", model.fontSize)).monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                Toggle("Ligatures", isOn: $model.ligatures)
            }
            Section("Cursor") {
                Picker("Shape", selection: $model.cursorStyle) {
                    Text("Block").tag(AnteConfig.Cursor.Style.block)
                    Text("Bar").tag(AnteConfig.Cursor.Style.bar)
                    Text("Underline").tag(AnteConfig.Cursor.Style.underline)
                }
                .pickerStyle(.segmented)
                Toggle("Blink", isOn: $model.cursorBlink)
            }
            if let updater = model.updater {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $model.automaticUpdates)
                    HStack(alignment: .top) {
                        Text("Checks raw.githubusercontent.com once a day for a new version; nothing else is sent.")
                            .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                        Spacer()
                        Button("Check Now") { updater.checkNow() }.disabled(!updater.canCheck)
                    }
                }
            }
            Section("Window") {
                Picker("⌘↩", selection: $model.fullScreenStyle) {
                    ForEach(AnteConfig.Window.FullScreenStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Either way the hotkey hides and shows the window as it is.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                Toggle("Open at a fixed size", isOn: $model.windowSizeIsFixed)
                if model.windowSizeIsFixed {
                    HStack {
                        Text("Window width")
                        Slider(value: $model.windowWidth, in: 0.3...1, step: 0.05)
                        Text(String(format: "%.0f%%", model.windowWidth * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("Window height")
                        Slider(value: $model.windowHeight, in: 0.3...1, step: 0.05)
                        Text(String(format: "%.0f%%", model.windowHeight * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    Text("Of the screen, from its top-left corner, each time Ante opens. Off: the window reopens where you left it.")
                        .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                }
            }
            Section("Show or hide Ante from any app") {
                KeyboardShortcuts.Recorder("Hotkey:", name: .showHideAnte)
                Picker("Animation", selection: $model.hotkeyAnimation) {
                    ForEach(AnteConfig.Hotkey.Animation.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Overlay width")
                    Slider(value: $model.hotkeyWidth, in: 0.3...1, step: 0.05)
                    Text(String(format: "%.0f%%", model.hotkeyWidth * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Overlay height")
                    Slider(value: $model.hotkeyHeight, in: 0.3...1, step: 0.05)
                    Text(String(format: "%.0f%%", model.hotkeyHeight * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle("Hide Ante again when another app takes focus", isOn: $model.hideOnFocusLoss)
                Text("One press drops this window over whatever you are doing, on the screen you are on, without switching apps, at this size docked to the top of the screen; the next press hides it again and the window gets its own size back. Nothing inside changes.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Picker("Theme", selection: $model.themeName) {
                ForEach(model.themeNames + (model.themeNames.contains("ante") ? [] : ["ante"]), id: \.self) { Text($0).tag($0) }
            }
            Picker("Appearance", selection: $model.appearance) {
                Text("System").tag(AnteConfig.Appearance.system)
                Text("Light").tag(AnteConfig.Appearance.light)
                Text("Dark").tag(AnteConfig.Appearance.dark)
            }
            .pickerStyle(.segmented)
            Button("Import Theme…") { ThemeImportPanel.run(model: model) }
            Section("Accent") {
                HStack(spacing: 8) {
                    ForEach(AnteAccent.presets, id: \.hex) { preset in
                        Button { model.accentHex = preset.hex } label: {
                            Circle()
                                .fill(AnteAccent.color(for: preset.hex))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary.opacity(model.accentHex == preset.hex ? 0.9 : 0), lineWidth: 2))
                                .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                        .accessibilityLabel("\(preset.name) accent")
                    }
                    Spacer()
                    ColorPicker("Custom", selection: $model.accentColor, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom accent")
                    Button("Reset") { model.accentHex = AnteStyle.defaultAccentHex }
                        .disabled(model.isDefaultAccent)
                }
                Text("Used for the focus ring, selection, and \"waiting for you\" badges. Stored as [theme] accent = \"\(model.accentHex)\".")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
            Section("Background") {
                HStack {
                    ColorPicker("Window background", selection: $model.backgroundColor, supportsOpacity: false)
                    Spacer()
                    Button("Use Theme's") { model.backgroundHex = nil }
                        .disabled(!model.hasCustomBackground)
                }
                HStack {
                    ColorPicker("Header", selection: $model.headerColor, supportsOpacity: false)
                    Spacer()
                    Button("Match Window") { model.headerHex = nil }
                        .disabled(!model.hasCustomHeader)
                }
                HStack {
                    Text("Opacity")
                    Slider(value: $model.windowOpacity, in: 0.01...1, step: 0.01)
                    Text(String(format: "%.0f%%", model.windowOpacity * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Blur")
                    Slider(value: $model.windowBlur, in: 0...1, step: 0.01)
                    Text(String(format: "%.0f%%", model.windowBlur * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(model.windowOpacity >= 1)
                Text("One colour for the terminal and the chrome around it; light or dark text follows it. The header (toolbar and the strip beside it) can take its own colour, e.g. a light bar over a dark terminal. Below 100% the desktop shows through the sidebar and terminal (the header stays solid), frosted so the text stays readable.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
            Section("Wallpaper") {
            HStack {
                TextField("Wallpaper path", text: $model.wallpaperPath, prompt: Text("~/Pictures/wallpaper.jpg"))
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url { model.wallpaperPath = url.path }
                }
                Button("Remove") { model.wallpaperPath = "" }
                    .disabled(model.wallpaperPath.isEmpty)
            }
            HStack {
                Text("Opacity")
                Slider(value: $model.wallpaperOpacity, in: 0...0.9)
                Text(String(format: "%.0f%%", model.wallpaperOpacity * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Blur")
                Slider(value: $model.wallpaperBlur, in: 0...40, step: 1)
                Text(String(format: "%.0f", model.wallpaperBlur)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            }
        }
        .formStyle(.grouped)
    }

    private var shell: some View {
        Form {
            TextField("Shell program", text: $model.shellProgram, prompt: Text("login shell"))
            Toggle("Shell integration (prompt marks, directory tracking)", isOn: $model.shellIntegration)
            Text("Integration is injected through the environment. Ante never edits your shell's rc files.")
                .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
        }
        .formStyle(.grouped)
    }

    private var keys: some View {
        Form {
            Section {
                ForEach(model.keyBindings, id: \.key) { item in
                    KeyBindingRow(label: item.label, binding: item.binding) { text in
                        model.setKeyBinding(item.key, text: text)
                    }
                }
            } footer: {
                Text("Write shortcuts as cmd+k, shift+cmd+p, ctrl+alt+up. Changes apply immediately.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var agents: some View {
        let _ = model.hookRevision
        return Form {
            Section("Waiting for you") {
                Toggle("Claude Code hook (definite signal)", isOn: $model.claudeHookInstalled)
                Text("Adds Notification, Stop, and UserPromptSubmit hooks to \(model.claudeSettingsPath) that append the event to Ante's own log under Application Support (emptied once it passes 256 KB; deleted when this is turned off). The settings file is backed up first; turning this off removes only Ante's entries.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                HStack {
                    Text("Quiet threshold")
                    Slider(value: $model.quietSeconds, in: 2...30, step: 1)
                    Text("\(Int(model.quietSeconds)) s").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Text("Without a hook, an agent that prints nothing for this long is shown as probably waiting.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
            Section("Notifications") {
                Toggle("Notify when a session is waiting for you", isOn: $model.notifyWaiting)
                Picker("Sound", selection: $model.notifySound) {
                    Text("None").tag("")
                    ForEach(model.notifySoundChoices, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!model.notifyWaiting)
                Text("A macOS notification with the session's name and why it stopped; click it to jump there. Nothing is sent for the pane you are already looking at. The Dock icon counts waiting sessions. The focus timer uses the same sound.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            }
            Section("History") {
                Picker("Claude Code keeps transcripts for", selection: $model.claudeRetentionDays) {
                    ForEach(SettingsModel.retentionChoices, id: \.days) { Text($0.label).tag($0.days) }
                    if !SettingsModel.retentionChoices.contains(where: { $0.days == model.claudeRetentionDays }) {
                        Text("\(model.claudeRetentionDays) days").tag(model.claudeRetentionDays)
                    }
                }
                Text("Claude Code deletes transcripts older than this on launch (cleanupPeriodDays in \(model.claudeSettingsPath)), and with them the sessions Ante can list and resume. Codex history is read as-is.")
                    .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
                Button("Clear Ante Session History", role: .destructive) { model.clearAnteHistory() }
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Toggle("Confirm before pasting multiple lines", isOn: $model.confirmMultilinePaste)
            Text("Quitting closes every session into History (name, folder and last command only — never the screen contents). Each launch starts with a fresh session.")
                .font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
            Text("Ante makes no network connections.").font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary)
        }
        .formStyle(.grouped)
    }
}


/// One rebindable shortcut: label, an editable text form, and the symbol form beside it.
private struct KeyBindingRow: View {
    let label: String
    let binding: KeyBinding
    let onCommit: (String) -> String?

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let error {
                Text(error).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.statusFailed)
            } else {
                Text(binding.display).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary).monospaced()
            }
            // In a grouped Form the first argument is a *label*; keep it empty and use a prompt.
            TextField("", text: $text, prompt: Text("cmd+k"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 130)
                .onSubmit { error = onCommit(text) }
        }
        .onAppear { text = binding.text }
        .onChange(of: binding) { _, new in text = new.text; error = nil }
    }
}
