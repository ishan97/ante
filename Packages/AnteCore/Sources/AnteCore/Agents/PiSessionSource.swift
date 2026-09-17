// Packages/AnteCore/Sources/AnteCore/Agents/PiSessionSource.swift
import Foundation

/// Pi (pi.dev) keeps one JSONL file per session under `~/.pi/agent/sessions/<cwd>/`: a
/// `{"type":"session"}` header (id, cwd, timestamp, optional title) — sometimes preceded by a
/// rewritable `{"type":"title"}` slot line — then `{"type":"message"}` entries. `pi --session <id>`
/// resumes one.
public struct PiSessionSource: Sendable {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/sessions")) {
        self.root = root
    }

    public func scan() -> [PastSession] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [PastSession] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            if let s = parse(file: file) { out.append(s) }
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func parse(file: URL) -> PastSession? {
        let records = JSONLines.head(of: file)
        var slotTitle: String?
        var header: [String: Any]?
        var firstPrompt: String?
        for r in records {
            switch r["type"] as? String {
            case "title": if slotTitle == nil { slotTitle = r["title"] as? String }
            case "session": if header == nil { header = r }
            case "message":
                guard firstPrompt == nil, let message = r["message"] as? [String: Any], message["role"] as? String == "user",
                      let text = Self.text(of: message), ClaudeSessionSource.isRealPrompt(text) else { continue }
                firstPrompt = text
            default: continue
            }
            if header != nil, firstPrompt != nil { break }
        }
        guard let header, let id = header["id"] as? String, let cwd = header["cwd"] as? String else { return nil }
        let created = (header["timestamp"] as? String).flatMap { ISO8601DateFormatter.anteFractional.date(from: $0) ?? ISO8601DateFormatter.antePlain.date(from: $0) }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created ?? Date()
        let title = (header["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slotTitle.flatMap { $0.isEmpty ? nil : $0 } ?? firstPrompt ?? "Pi session"
        let branched = header["parentSession"] != nil || header["branchedFrom"] != nil
        return PastSession(id: id, agent: .pi, title: ClaudeSessionSource.clean(title), projectPath: cwd,
                           createdAt: created ?? modified, modifiedAt: modified, detail: branched ? "branch" : nil,
                           resumeCommand: AgentKind.pi.resumeCommand(sessionID: id))
    }

    /// One event per user prompt across every session file, for the Activity strip.
    public func events() -> [ActivityEvent] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [ActivityEvent] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            var sessionID = file.deletingPathExtension().lastPathComponent
            for r in JSONLines.parse(HistoryTail.read(file)) {
                switch r["type"] as? String {
                case "session": if let id = r["id"] as? String { sessionID = id }
                case "message":
                    guard let message = r["message"] as? [String: Any], message["role"] as? String == "user",
                          let stamp = r["timestamp"] as? String,
                          let at = ISO8601DateFormatter.anteFractional.date(from: stamp) ?? ISO8601DateFormatter.antePlain.date(from: stamp) else { continue }
                    out.append(ActivityEvent(at: at, sessionID: sessionID, agent: .pi))
                default: continue
                }
            }
        }
        return out
    }

    /// The text blocks of a message, joined. Pi stores content as blocks; older files as a string.
    static func text(of message: [String: Any]) -> String? {
        if let s = message["content"] as? String { return s }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}
