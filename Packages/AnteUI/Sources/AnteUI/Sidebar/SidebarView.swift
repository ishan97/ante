// Packages/AnteUI/Sources/AnteUI/Sidebar/SidebarView.swift
import SwiftUI
import AppKit
import AnteCore
import AnteTerm

struct SidebarView: View {

    @Environment(\.anteChrome) private var chrome

    @Environment(\.anteAccent) private var accent
    @Bindable var runtime: WorkspaceRuntime

    var body: some View {
        VStack(spacing: 0) {
            // Clear the traffic lights: the window has no title bar, so the sidebar starts under them.
            Color.clear.frame(height: AnteStyle.toolbarHeight)
            sessionsEntry
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(runtime.store.state.orderedProjects) { project in
                        projectSection(project)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            Divider().overlay(AnteStyle.hairline)
            footer
        }
        .frame(width: AnteStyle.sidebarWidth)
        // The strip under the traffic lights is the toolbar's colour and solid, in front of the
        // translucent sidebar background so nothing tints it.
        .background(alignment: .top) {
            chrome.toolbar(AnteStyle.toolbarBackground).frame(height: AnteStyle.toolbarHeight)
        }
        .background(chrome.sidebar(AnteStyle.sidebarBackground))
    }

    /// Pinned above the projects: the Sessions board, with a count of panes waiting on you.
    private var sessionsEntry: some View {
        let selected = runtime.isSessionsViewerVisible
        let waiting = runtime.board?.waitingCount ?? 0
        return HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? accent : AnteStyle.textSecondary)
                .frame(width: 16)
            Text("Sessions")
                .font(selected ? AnteStyle.uiFontSemibold : AnteStyle.uiFont)
                .foregroundStyle(AnteStyle.textPrimary)
            Spacer()
            if waiting > 0 {
                Text("\(waiting)")
                    .font(AnteStyle.captionFont).monospacedDigit()
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(accent, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).fill(selected ? AnteStyle.rowSelected : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { runtime.isSessionsViewerVisible.toggle() }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .help("Sessions (\(runtime.config.keys.sessionsBoard.display))")
    }

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        projectHeader(project)
        ForEach(runtime.store.visibleSessions(in: project.id)) { session in
            sessionRow(session)
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        SessionRow(
            session: session,
            isSelected: runtime.store.state.focusedSessionID == session.id && !runtime.isSessionsViewerVisible,
            isWaiting: runtime.board?.isWaiting(session: session.id) ?? false,
            controller: liveController(for: session.id),
            onSelect: { runtime.open(session: session.id) },
            onRename: { name in runtime.store.renameSession(session.id, to: name) },
            onClose: { runtime.closeSession(session.id) }
        )
        .padding(.horizontal, 8)
    }

    private func projectHeader(_ project: Project) -> some View {
        HStack {
            Text(project.name.uppercased())
                .font(AnteStyle.captionFont)
                .tracking(0.6)
                .foregroundStyle(AnteStyle.textSecondary)
                .lineLimit(1)
            Spacer()
            Button {
                runtime.newSession(in: project.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            .help("New session in \(project.name)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contextMenu {
            Button("New Session") { runtime.newSession(in: project.id) }
            Button("Remove Project", role: .destructive) { runtime.removeProject(project.id) }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                addProject()
            } label: {
                Label("Add Project…", systemImage: "folder.badge.plus")
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private func liveController(for session: SessionID) -> TerminalSessionController? {
        guard let layout = runtime.existingLayout(for: session), let pane = layout.paneIDs.first else { return nil }
        return runtime.controller(for: pane)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a project folder"
        if panel.runModal() == .OK, let url = panel.url {
            let project = runtime.store.addProject(rootDirectory: url)
            runtime.newSession(in: project.id)
        }
    }
}
