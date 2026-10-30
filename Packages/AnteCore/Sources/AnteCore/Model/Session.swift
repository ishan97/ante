// Packages/AnteCore/Sources/AnteCore/Model/Session.swift
import Foundation

/// A named terminal session in the sidebar. By default it lives for one run of the app: on quit
/// it is filed into History (name, cwd, last command) and the next launch starts fresh. With
/// `[sessions] restore` it is kept, with its layout, and reopened on the next launch.
public struct Session: Hashable, Codable, Sendable, Identifiable {
    public let id: SessionID
    public var projectID: ProjectID
    public var name: String
    public var workingDirectory: URL
    public var lastCommand: String?
    /// Ordering within its project; lower comes first.
    public var order: Int
    public var createdAt: Date
    /// The hotkey panel's session. Hidden from the sidebar.
    public var isScratch: Bool
    /// True once the user renamed it; agent-provided names then never replace theirs.
    public var isUserNamed: Bool
    /// Its panes as they last stood, kept current while it runs; `[sessions] restore` rebuilds
    /// them on the next launch. Nil for a session that has not been opened.
    public var layout: SavedLayout?

    public init(
        id: SessionID = SessionID(),
        projectID: ProjectID,
        name: String,
        workingDirectory: URL,
        lastCommand: String? = nil,
        order: Int = 0,
        createdAt: Date = Date(),
        isScratch: Bool = false,
        isUserNamed: Bool = false,
        layout: SavedLayout? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.workingDirectory = workingDirectory
        self.lastCommand = lastCommand
        self.order = order
        self.createdAt = createdAt
        self.isScratch = isScratch
        self.isUserNamed = isUserNamed
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, name, workingDirectory, lastCommand, order, createdAt, isScratch, isUserNamed, layout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(SessionID.self, forKey: .id)
        projectID = try c.decode(ProjectID.self, forKey: .projectID)
        name = try c.decode(String.self, forKey: .name)
        workingDirectory = try c.decode(URL.self, forKey: .workingDirectory)
        lastCommand = try c.decodeIfPresent(String.self, forKey: .lastCommand)
        order = try c.decode(Int.self, forKey: .order)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Added after schema 1 shipped; absent means false. No schema bump needed.
        isScratch = try c.decodeIfPresent(Bool.self, forKey: .isScratch) ?? false
        isUserNamed = try c.decodeIfPresent(Bool.self, forKey: .isUserNamed) ?? false
        // A layout this build cannot read is dropped, not fatal: the session reopens as one pane.
        layout = (try? c.decodeIfPresent(SavedLayout.self, forKey: .layout)) ?? nil
    }
}
