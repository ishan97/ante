// Packages/AnteCore/Sources/AnteCore/Agents/AnteSessionHistoryStore.swift
import Foundation

/// Ante sessions the user closed, so they can be reopened from History.
public struct ClosedSession: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var workingDirectory: String
    public var projectPath: String
    public var lastCommand: String?
    public var agent: AgentKind
    public var closedAt: Date
    /// The agent's own id for the conversation, when Ante knew it. Absent in entries filed
    /// before 1.6.
    public var agentSessionID: String?

    public init(id: String = UUID().uuidString, name: String, workingDirectory: String, projectPath: String,
                lastCommand: String?, agent: AgentKind, closedAt: Date = Date(), agentSessionID: String? = nil) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectPath = projectPath
        self.lastCommand = lastCommand
        self.agent = agent
        self.closedAt = closedAt
        self.agentSessionID = agentSessionID
    }

    /// Picking it up again resumes the exact conversation when its id is known, else opens the
    /// agent's session picker in the folder: never a bare shell, which looks like nothing happened.
    /// The command is rebuilt from the agent and the (validated) id, never read from the file.
    public var resumeCommand: String? {
        agentSessionID.flatMap { agent.resumeCommand(sessionID: $0) } ?? agent.pickerCommand
    }

    public var asPastSession: PastSession {
        PastSession(id: "ante-\(id)", agent: agent, title: name, projectPath: workingDirectory,
                    createdAt: closedAt, modifiedAt: closedAt, detail: lastCommand, resumeCommand: resumeCommand)
    }
}

public struct AnteSessionHistoryStore: Sendable {
    public static let capacity = 500
    private let file: URL

    public init(paths: AppPaths) {
        self.file = paths.historyFile
    }

    /// Newest first. Plain shells and one-off commands are left out even if an older version
    /// of Ante filed them: there is nothing to resume in a closed shell.
    public func all() -> [ClosedSession] {
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder.anteHistory.decode([ClosedSession].self, from: data) else { return [] }
        return list.filter { $0.agent.isAgent }.sorted { $0.closedAt > $1.closedAt }
    }

    public func append(_ session: ClosedSession) throws {
        try append(contentsOf: [session])
    }

    /// One read and one atomic write however many sessions close at once (quit).
    public func append(contentsOf sessions: [ClosedSession]) throws {
        let sessions = sessions.filter { $0.agent.isAgent }
        guard !sessions.isEmpty else { return }
        var list = all()
        list.insert(contentsOf: sessions.sorted { $0.closedAt > $1.closedAt }, at: 0)
        if list.count > Self.capacity { list = Array(list.prefix(Self.capacity)) }
        try AtomicFile.write(try JSONEncoder.anteHistory.encode(list), to: file)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}

extension JSONEncoder {
    static var anteHistory: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
extension JSONDecoder {
    static var anteHistory: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
