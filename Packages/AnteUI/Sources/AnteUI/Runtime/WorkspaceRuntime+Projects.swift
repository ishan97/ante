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
}
