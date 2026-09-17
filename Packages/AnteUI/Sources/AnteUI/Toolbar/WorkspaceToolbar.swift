// Packages/AnteUI/Sources/AnteUI/Toolbar/WorkspaceToolbar.swift
import SwiftUI
import AnteCore

struct WorkspaceToolbar: View {

    @Environment(\.anteChrome) private var chrome
    @Environment(\.anteAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var runtime: WorkspaceRuntime

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { runtime.isSidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(runtime.config.keys.toggleSidebar.shortcut)
            .help("Toggle Sidebar (\(runtime.config.keys.toggleSidebar.display))")

            if let session = runtime.store.focusedSession {
                Text(session.name)
                    .font(AnteStyle.uiFontSemibold)
                    .foregroundStyle(AnteStyle.textPrimary)
                if let pane = runtime.focusedPaneID, let dir = runtime.controller(for: pane).currentDirectory {
                    Text(Self.abbreviatedPath(dir))
                        .font(AnteStyle.monoCaption)
                        .foregroundStyle(AnteStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                pomodoroButton
                scratchpadButton
                Divider().frame(height: 14).padding(.horizontal, 2)
                toolbarButton(runtime.isDarkAppearance ? "sun.max" : "moon",
                              help: (runtime.isDarkAppearance ? "Switch to Light" : "Switch to Dark")
                                    + (runtime.hasCustomBackground ? " (clears the custom window background)" : "")) { runtime.toggleAppearance() }
                    .accessibilityIdentifier("toggle-appearance")
                toolbarButton("doc.badge.plus", help: "Insert File Path (\(runtime.config.keys.insertFile.display))") { runtime.insertFilePaths() }
                Divider().frame(height: 14).padding(.horizontal, 2)
                toolbarButton("rectangle.lefthalf.inset.filled", help: "Split Left (\(runtime.config.keys.splitLeft.display))") { runtime.splitFocusedPane(axis: .horizontal, before: true) }
                toolbarButton("rectangle.righthalf.inset.filled", help: "Split Right (\(runtime.config.keys.splitRight.display))") { runtime.splitFocusedPane(axis: .horizontal) }
                toolbarButton("rectangle.tophalf.inset.filled", help: "Split Up (\(runtime.config.keys.splitUp.display))") { runtime.splitFocusedPane(axis: .vertical, before: true) }
                toolbarButton("rectangle.bottomhalf.inset.filled", help: "Split Down (\(runtime.config.keys.splitDown.display))") { runtime.splitFocusedPane(axis: .vertical) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                runtime.headerControlsWidth = width + 12 + 8   // trailing padding plus a little slack
            }
        }
        .padding(.leading, runtime.isSidebarVisible ? 12 : 84)   // clear the traffic lights when the sidebar is hidden
        .padding(.trailing, 12)
        .frame(height: AnteStyle.toolbarHeight)
        .background(chrome.toolbar(AnteStyle.toolbarBackground))
        // A custom header colour brings its own light/dark text.
        .environment(\.colorScheme, chrome.headerIsDark.map { $0 ? .dark : .light } ?? colorScheme)
    }

    /// The timer button shows the time left while a block runs, in the phase's colour.
    private var pomodoroButton: some View {
        let model = runtime.pomodoro
        let color = model.phase == .focus ? accent : AnteStyle.statusOK
        return Button {
            runtime.isPomodoroVisible.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.isRunning ? "timer" : "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isActive ? color : AnteStyle.textSecondary)
                if model.isActive {
                    Text(model.display)
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(model.state == .paused ? AnteStyle.textSecondary : color)
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.isActive ? "\(model.phase.label) — \(model.display)" : "Focus timer")
        .popover(isPresented: $runtime.isPomodoroVisible, arrowEdge: .bottom) {
            PomodoroView(model: runtime.pomodoro)
        }
    }

    /// The checklist button wears the number of open to-dos, and anchors the popover.
    private var scratchpadButton: some View {
        let open = runtime.scratchpad.openCount
        return Button {
            runtime.isScratchpadVisible.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(open > 0 ? accent : AnteStyle.textSecondary)
                if open > 0 {
                    Text("\(open)")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(accent, in: Capsule())
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("To-do & Notes (\(runtime.config.keys.scratchpad.display))")
        .popover(isPresented: $runtime.isScratchpadVisible, arrowEdge: .bottom) {
            ScratchpadView(model: runtime.scratchpad)
        }
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AnteStyle.textSecondary)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
