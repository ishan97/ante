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
    /// The account that last ran this conversation (`AgentAccount.id`), when Ante recorded it.
    public var accountID: String?
    /// The agent's own conversation id, for a row whose `id` is not it (Ante's closed-session
    /// rows are `ante-<uuid>`). Nil: `id` is the conversation id.
    public var agentSessionID: String?

    /// The id the agent knows this conversation by, if any: what a running agent reports, and
    /// what "is it already open in a pane?" must compare against.
    public var conversationID: String? {
        agentSessionID ?? (id.hasPrefix("ante-") ? nil : id)
    }

    public init(id: String, agent: AgentKind, title: String, projectPath: String, createdAt: Date, modifiedAt: Date,
                detail: String? = nil, resumeCommand: String?, accountID: String? = nil, agentSessionID: String? = nil) {
        self.id = id
        self.agent = agent
        self.title = title
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.detail = detail
        self.resumeCommand = resumeCommand
        self.accountID = accountID
        self.agentSessionID = agentSessionID
    }

    public var projectName: String { (projectPath as NSString).lastPathComponent }
}
