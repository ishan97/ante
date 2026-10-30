// Packages/AnteUI/Sources/AnteUI/Runtime/WorkspaceRuntime+Projects.swift
import Foundation
import AnteCore

extension WorkspaceRuntime {
    /// Closes every session in the project (killing their shells) and removes it.
    public func removeProject(_ id: ProjectID) {
        for session in store.state.sessions where session.projectID == id && !session.isScratch {
            closeSession(session.id)
        }
        store.removeProject(id)
        if store.state.projects.isEmpty {
            let home = store.addProject(rootDirectory: FileManager.default.homeDirectoryForCurrentUser)
            store.renameProject(home.id, to: "Home")
            open(session: store.addSession(in: home.id).id)
        }
    }

    // MARK: - New folder

    /// What the New Folder popover is making. Lives on the runtime, not in the view, so the typed
    /// name survives the popover closing while the folder chooser is up.
    public struct NewFolderRequest: Equatable {
        /// The folder the new one goes in.
        public var parent: URL
        /// The project whose header the popover hangs off; nil for the sidebar's footer button.
        public var anchor: ProjectID?
        public var name = ""

        public init(parent: URL, anchor: ProjectID? = nil) {
            self.parent = parent
            self.anchor = anchor
        }
    }

    /// Opens the New Folder popover: beside the latest project from the footer or the palette, or
    /// inside `project` from its context menu.
    public func showNewFolder(inside project: Project? = nil) {
        newFolder = NewFolderRequest(parent: project?.rootDirectory ?? defaultNewFolderParent, anchor: project?.id)
    }

    /// Why a new project folder could not be made, worded for the field under the name.
    public enum NewFolderError: Error, Equatable, LocalizedError {
        case emptyName
        case invalidName
        case alreadyExists(String)
        case noParent(String)
        case couldNotCreate(String)

        public var errorDescription: String? {
            switch self {
            case .emptyName: return "Give the folder a name."
            case .invalidName: return "A folder name cannot contain “/” or “:”, or be “.” or “..”."
            case let .alreadyExists(name): return "“\(name)” already exists there. Use Add Project… to open it."
            case let .noParent(path): return "\(path) is not a folder."
            case let .couldNotCreate(reason): return reason
            }
        }
    }

    /// Where the New Folder field puts a folder unless told otherwise: beside the most recently
    /// added project (people keep their projects together), or the home folder.
    public var defaultNewFolderParent: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let latest = store.state.projects
            .filter { $0.rootDirectory.standardizedFileURL.path != home.path }
            .max { $0.order < $1.order }
        return latest?.rootDirectory.deletingLastPathComponent() ?? home
    }

    /// Creates `name` inside `parent`, adds it as a project and opens a session in it.
    @discardableResult
    public func createProjectFolder(named rawName: String, in parent: URL) throws -> Project {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw NewFolderError.emptyName }
        guard !name.contains("/"), !name.contains(":"), name != ".", name != ".." else { throw NewFolderError.invalidName }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NewFolderError.noParent(parent.path)
        }
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw NewFolderError.alreadyExists(name) }
        do {
            // Not intermediate: the parent was checked above, and a typo must not grow a tree.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw NewFolderError.couldNotCreate(error.localizedDescription)
        }
        let project = store.addProject(rootDirectory: folder)
        newSession(in: project.id)
        return project
    }
}
