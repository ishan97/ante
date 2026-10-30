// Packages/AnteUI/Sources/AnteUI/Sidebar/NewFolderView.swift
import SwiftUI
import AppKit

/// The New Folder popover: a name, where it goes (beside the latest project, or inside the
/// project it was opened from, unless changed), and Create — which makes the folder, adds it as a
/// project and opens a session in it.
struct NewFolderView: View {
    @Bindable var runtime: WorkspaceRuntime
    @State private var error: String?
    @FocusState private var isNameFocused: Bool

    private var parent: URL { runtime.newFolder?.parent ?? runtime.defaultNewFolderParent }
    private var name: Binding<String> {
        Binding(get: { runtime.newFolder?.name ?? "" },
                set: { runtime.newFolder?.name = $0; error = nil })
    }
    private var canCreate: Bool { !name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Project Folder")
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
            TextField("Folder name", text: name, prompt: Text("my-project"))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(create)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(AnteStyle.textSecondary)
                Text("In \(Self.display(parent))")
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(parent.path)
                Spacer(minLength: 4)
                Button("Change…", action: chooseParent)
                    .controlSize(.small)
            }
            if let error {
                Text(error)
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.statusFailed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { runtime.newFolder = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard canCreate else { return }
        do {
            try runtime.createProjectFolder(named: name.wrappedValue, in: parent)
            runtime.newFolder = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chooseParent() {
        // The popover may close while the panel has the keyboard; put the request (and the name
        // typed so far) back afterwards so it reopens as it was.
        guard var request = runtime.newFolder else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = request.parent
        panel.prompt = "Choose"
        panel.message = "Choose where the new folder goes"
        if panel.runModal() == .OK, let url = panel.url {
            request.parent = url
            error = nil
        }
        request.name = runtime.newFolder?.name ?? request.name
        runtime.newFolder = request
        isNameFocused = true
    }

    static func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
