// Packages/AnteCore/Sources/AnteCore/Model/SavedLayout.swift
import Foundation

/// A session's panes as they stood, so `[sessions] restore` can rebuild them on the next launch.
/// Mirrors the UI's split tree without its runtime pane IDs.
public indirect enum SavedLayout: Hashable, Codable, Sendable {
    public enum Axis: String, Hashable, Codable, Sendable {
        /// Panes side by side.
        case horizontal
        /// Panes stacked.
        case vertical
    }

    case pane(SavedPane)
    case split(Axis, ratio: Double, first: SavedLayout, second: SavedLayout)

    /// Leaves in display order (left/top first), the same order as the split tree's panes.
    public var panes: [SavedPane] {
        switch self {
        case let .pane(pane): return [pane]
        case let .split(_, _, first, second): return first.panes + second.panes
        }
    }
}

/// One pane: its folder and, when an agent was in the foreground, how to bring it back.
public struct SavedPane: Hashable, Codable, Sendable {
    public var workingDirectory: URL
    /// The agent in the foreground when the layout was saved; nil for a shell or a plain command
    /// (a command is never re-run: it may not be safe to repeat).
    public var agent: AgentKind?
    /// The agent's own session id, when known, so the exact conversation resumes.
    public var agentSessionID: String?
    /// False when another pane ran the same agent in the same folder: "continue the latest here"
    /// would give both panes one conversation, so without an id the agent's picker opens instead.
    public var mayContinueLatest: Bool

    public init(workingDirectory: URL, agent: AgentKind? = nil, agentSessionID: String? = nil, mayContinueLatest: Bool = true) {
        self.workingDirectory = workingDirectory
        self.agent = agent
        self.agentSessionID = agentSessionID
        self.mayContinueLatest = mayContinueLatest
    }

    private enum CodingKeys: String, CodingKey { case workingDirectory, agent, agentSessionID, mayContinueLatest }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try c.decode(URL.self, forKey: .workingDirectory)
        agent = try c.decodeIfPresent(AgentKind.self, forKey: .agent)
        agentSessionID = try c.decodeIfPresent(String.self, forKey: .agentSessionID)
        mayContinueLatest = try c.decodeIfPresent(Bool.self, forKey: .mayContinueLatest) ?? true
    }

    /// What to type into the pane's fresh shell to bring its agent back, if anything.
    public var resumeCommand: String? {
        guard let agent, agent.isAgent else { return nil }
        if let agentSessionID, let exact = agent.resumeCommand(sessionID: agentSessionID) { return exact }
        return mayContinueLatest ? agent.continueCommand : agent.pickerCommand
    }
}
