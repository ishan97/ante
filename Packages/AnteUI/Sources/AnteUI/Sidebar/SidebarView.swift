// Packages/AnteUI/Sources/AnteUI/Sidebar/SidebarView.swift
import SwiftUI
import AppKit
import AnteCore
import AnteTerm

struct SidebarView: View {

    @Environment(\.anteChrome) private var chrome

    @Environment(\.anteAccent) private var accent
    @Bindable var runtime: WorkspaceRuntime

    /// The scrolling list's own coordinate space: rows, headers and the drag all report in it.
    nonisolated static let listSpace = "ante.sidebar.list"

    /// A session being dragged to another place or project.
    private struct SessionDrag: Equatable {
        let session: SessionID
        let name: String
        var location: CGPoint
        var target: SidebarDropTarget?
    }

    @State private var drag: SessionDrag?
    @State private var rowFrames: [SessionID: CGRect] = [:]
    @State private var headerFrames: [ProjectID: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Clear the traffic lights: the window has no title bar, so the sidebar starts under them.
            Color.clear.frame(height: AnteStyle.toolbarHeight)
            sessionsEntry
            ScrollView {
                // Not lazy: a drag needs the frames of every row, and rows a lazy stack has not
                // built (or has let go of) would report none, or stale ones.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(runtime.store.state.orderedProjects) { project in
                        projectSection(project)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
                .overlay(alignment: .topLeading) { dragOverlay }
                .coordinateSpace(name: Self.listSpace)
                // A row closed mid-drag never reports its drop: let go of it here, and of the
                // frames of rows and headers that are gone.
                .onChange(of: runtime.store.state.sessions.map(\.id)) { _, ids in
                    let live = Set(ids)
                    if let session = drag?.session, !live.contains(session) { drag = nil }
                    rowFrames = rowFrames.filter { live.contains($0.key) }
                }
                .onChange(of: runtime.store.state.projects.map(\.id)) { _, ids in
                    let live = Set(ids)
                    headerFrames = headerFrames.filter { live.contains($0.key) }
                }
                .onDisappear { drag = nil }
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
            onClose: { runtime.closeSession(session.id) },
            moveTargets: runtime.store.state.orderedProjects.filter { $0.id != session.projectID },
            onMove: { project in runtime.store.moveSession(session.id, to: project, at: .max) },
            onDrag: { location in dragChanged(session, to: location) },
            onDrop: { location in dropped(session.id, at: location) },
            isDragged: drag?.session == session.id
        )
        .padding(.horizontal, 8)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { rowFrames[session.id] = $0 }
    }

    // MARK: - Drag and drop

    private func dragChanged(_ session: Session, to location: CGPoint) {
        var next = drag ?? SessionDrag(session: session.id, name: session.name, location: location)
        next.location = location
        next.target = SidebarDropTarget.at(location, width: AnteStyle.sidebarWidth, sections: dropSections(), dragging: session.id)
        if next != drag { drag = next }
    }

    /// `location` nil: the drag was cancelled.
    private func dropped(_ session: SessionID, at location: CGPoint?) {
        defer { drag = nil }
        guard let location, drag?.session == session,
              let target = SidebarDropTarget.at(location, width: AnteStyle.sidebarWidth, sections: dropSections(), dragging: session) else { return }
        runtime.store.moveSession(session, to: target.project, at: target.index)
    }

    private func dropSections() -> [SidebarDropTarget.Section] {
        runtime.store.state.orderedProjects.compactMap { project in
            guard let header = headerFrames[project.id] else { return nil }
            let rows = runtime.store.visibleSessions(in: project.id).compactMap { s in rowFrames[s.id].map { (id: s.id, frame: $0) } }
            return SidebarDropTarget.Section(project: project.id, header: header, rows: rows)
        }
    }

    /// The insertion line, and the dragged session's name following the pointer.
    @ViewBuilder
    private var dragOverlay: some View {
        if let drag {
            ZStack(alignment: .topLeading) {
                if let target = drag.target {
                    Capsule()
                        .fill(accent)
                        .frame(width: AnteStyle.sidebarWidth - 28, height: 2)
                        .offset(x: 14, y: target.lineY - 1)
                }
                Text(drag.name)
                    .font(AnteStyle.uiFontSemibold)
                    .foregroundStyle(AnteStyle.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).fill(AnteStyle.rowSelected))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .frame(maxWidth: AnteStyle.sidebarWidth - 40, alignment: .leading)
                    .offset(x: 20, y: drag.location.y - 12)
                    .opacity(drag.target == nil ? 0.5 : 0.95)
            }
            .allowsHitTesting(false)
        }
    }

    private func projectHeader(_ project: Project) -> some View {
        let isDropTarget = drag?.target?.project == project.id
            && runtime.store.state.sessions.first { $0.id == drag?.session }?.projectID != project.id
        return HStack {
            Text(project.name.uppercased())
                .font(AnteStyle.captionFont)
                .tracking(0.6)
                .foregroundStyle(isDropTarget ? accent : AnteStyle.textSecondary)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.listSpace)) } action: { headerFrames[project.id] = $0 }
        .popover(isPresented: isNewFolderVisible(anchor: project.id), arrowEdge: .trailing) {
            NewFolderView(runtime: runtime)
        }
        .contextMenu {
            Button("New Session") { runtime.newSession(in: project.id) }
            Button("New Folder Inside…") { runtime.showNewFolder(inside: project) }
            Divider()
            Button("Remove Project", role: .destructive) { runtime.removeProject(project.id) }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                addProject()
            } label: {
                Label("Add Project…", systemImage: "folder")
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Open an existing folder as a project")
            Spacer()
            Button {
                runtime.showNewFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(AnteStyle.textSecondary)
            }
            .buttonStyle(.plain)
            .help("New Project Folder…")
            .accessibilityLabel("New Project Folder")
            .popover(isPresented: isNewFolderVisible(anchor: nil), arrowEdge: .top) {
                NewFolderView(runtime: runtime)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    /// The New Folder popover shows on the footer button (`anchor` nil) or on the header of the
    /// project it was asked for from.
    private func isNewFolderVisible(anchor: ProjectID?) -> Binding<Bool> {
        Binding(get: { runtime.newFolder.map { $0.anchor == anchor } ?? false },
                set: { if !$0, runtime.newFolder?.anchor == anchor { runtime.newFolder = nil } })
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
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        panel.message = "Choose a project folder"
        if panel.runModal() == .OK, let url = panel.url {
            let project = runtime.store.addProject(rootDirectory: url)
            runtime.newSession(in: project.id)
        }
    }
}
