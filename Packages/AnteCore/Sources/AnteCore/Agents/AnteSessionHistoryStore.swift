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

    public init(id: String = UUID().uuidString, name: String, workingDirectory: String, projectPath: String,
                lastCommand: String?, agent: AgentKind, closedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.projectPath = projectPath
        self.lastCommand = lastCommand
        self.agent = agent
        self.closedAt = closedAt
    }

    public var asPastSession: PastSession {
        PastSession(id: "ante-\(id)", agent: agent == .shell ? .shell : agent, title: name, projectPath: workingDirectory,
                    createdAt: closedAt, modifiedAt: closedAt, detail: lastCommand, resumeCommand: nil)
    }
}

public struct AnteSessionHistoryStore: Sendable {
    public static let capacity = 500
    private let file: URL

    public init(paths: AppPaths) {
        self.file = paths.historyFile
    }

    public func all() -> [ClosedSession] {
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder.anteHistory.decode([ClosedSession].self, from: data) else { return [] }
        return list.sorted { $0.closedAt > $1.closedAt }
    }

    public func append(_ session: ClosedSession) throws {
        try append(contentsOf: [session])
    }

    /// One read and one atomic write however many sessions close at once (quit).
    public func append(contentsOf sessions: [ClosedSession]) throws {
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
