import Foundation

/// Everything Ante persists between launches: projects, the sessions of the current run, focus.
public struct AppState: Hashable, Codable, Sendable {
    /// Bump when the on-disk shape changes, and add a migration in `Migrations`.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var projects: [Project]
    public var sessions: [Session]
    public var focusedSessionID: SessionID?

    public init(
        schemaVersion: Int = AppState.currentSchemaVersion,
        projects: [Project] = [],
        sessions: [Session] = [],
        focusedSessionID: SessionID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.sessions = sessions
        self.focusedSessionID = focusedSessionID
    }

    public static let empty = AppState()

    /// Sessions belonging to a project, in sidebar order.
    public func sessions(in projectID: ProjectID) -> [Session] {
        sessions.filter { $0.projectID == projectID }.sorted { $0.order < $1.order }
    }

    /// Projects in sidebar order.
    public var orderedProjects: [Project] {
        projects.sorted { $0.order < $1.order }
    }
}
