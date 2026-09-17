// Packages/AnteUI/Sources/AnteUI/Sidebar/SessionRow.swift
import SwiftUI
import AnteCore
import AnteTerm

struct SessionRow: View {

    @Environment(\.anteAccent) private var accent
    let session: Session
    let isSelected: Bool
    var isWaiting = false
    let controller: TerminalSessionController?
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @State private var isPressed = false
    @State private var lastPressAt: Date?
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Hollow until the session has been opened this launch; filled and coloured once live.
            Circle()
                .strokeBorder(AnteStyle.statusExited, lineWidth: controller == nil ? 1 : 0)
                .background(Circle().fill(controller == nil ? Color.clear : statusColor))
                .frame(width: 7, height: 7)
                .padding(.leading, 6)
            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(AnteStyle.uiFont)
                    .focused($editorFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isEditing = false }
            } else {
                Text(session.name)
                    .font(isSelected ? AnteStyle.uiFontSemibold : AnteStyle.uiFont)
                    .foregroundStyle(AnteStyle.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let subtitle {
                Text(subtitle)
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous)
                .fill(isSelected ? AnteStyle.rowSelected : (isHovering ? AnteStyle.rowHover : Color.clear))
        )
        .contentShape(Rectangle())
        // Select on mouse-down like a native source list. A second `onTapGesture(count: 2)`
        // would make SwiftUI hold every single click for the double-click interval first.
        .gesture(pressGesture, including: isEditing ? .none : .all)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename") { beginRename() }
            Button("Close Session", role: .destructive) { onClose() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(accessibilityStatus)")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                let now = Date()
                if let last = lastPressAt, now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
                    lastPressAt = nil
                    beginRename()
                } else {
                    lastPressAt = now
                    onSelect()
                }
            }
            .onEnded { _ in isPressed = false }
    }

    private var statusColor: Color {
        if isWaiting { return accent }
        guard let controller else { return AnteStyle.statusExited }
        switch controller.state {
        case .idle: return AnteStyle.statusExited
        case .failed, .exited: return AnteStyle.statusExited
        case .running:
            if controller.activity == .commandRunning { return AnteStyle.statusRunning }
            if let code = controller.lastExitCode, code != 0 { return AnteStyle.statusFailed }
            return AnteStyle.statusOK
        }
    }

    private var accessibilityStatus: String {
        guard let controller, controller.state == .running else { return "not running" }
        return controller.activity == .commandRunning ? "running a command" : "idle"
    }

    private var subtitle: String? {
        guard let controller else { return nil }
        if case let .exited(code) = controller.state { return "exited \(code.map(String.init) ?? "")".trimmingCharacters(in: .whitespaces) }
        if let dir = controller.currentDirectory { return Self.abbreviate(dir) }
        return nil
    }

    static func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = url.path
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        return path == "~" ? "~" : (url.lastPathComponent.isEmpty ? path : url.lastPathComponent)
    }

    private func beginRename() {
        draft = session.name
        isEditing = true
        editorFocused = true
    }

    private func commitRename() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != session.name { onRename(trimmed) }
        isEditing = false
    }
}
