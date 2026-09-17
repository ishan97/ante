// Packages/AnteCore/Sources/AnteCore/Agents/PastSession.swift
import Foundation

/// One row of the history list, from any source.
public struct PastSession: Identifiable, Hashable, Sendable {
    public let id: String
    public let agent: AgentKind
    public var title: String
    public let projectPath: String
    public let createdAt: Date
    public let modifiedAt: Date
    /// e.g. Codex "exec" vs "cli"; shown as a caption.
    public let detail: String?
    /// Typed into the resumed shell. Nil = just reopen in the folder.
    public let resumeCommand: String?

    public init(id: String, agent: AgentKind, title: String, projectPath: String, createdAt: Date, modifiedAt: Date,
                detail: String? = nil, resumeCommand: String?) {
        self.id = id
        self.agent = agent
        self.title = title
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.detail = detail
        self.resumeCommand = resumeCommand
    }

    public var projectName: String { (projectPath as NSString).lastPathComponent }
}
