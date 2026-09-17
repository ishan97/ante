// Packages/AnteCore/Sources/AnteCore/Agents/CodexSessionSource.swift
import Foundation

/// Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl`; the first line is
/// `session_meta` (id, cwd, source) and the first `event_msg/user_message` is the prompt.
public struct CodexSessionSource: Sendable {
    public let root: URL
    /// Sessions Codex has archived (`codex resume` still accepts them).
    public let archivedRoot: URL?

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
                archivedRoot: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")) {
        self.root = root
        self.archivedRoot = archivedRoot
    }

    public func scan() -> [PastSession] {
        var out: [PastSession] = []
        var seen = Set<String>()
        for directory in [root, archivedRoot].compactMap({ $0 }) {
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                if let s = parse(file: file), seen.insert(s.id).inserted { out.append(s) }
            }
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func parse(file: URL) -> PastSession? {
        let records = JSONLines.head(of: file)
        guard let meta = records.first(where: { $0["type"] as? String == "session_meta" })?["payload"] as? [String: Any],
              let id = meta["id"] as? String, let cwd = meta["cwd"] as? String else { return nil }
        let source = meta["source"] as? String
        let created = (meta["timestamp"] as? String).flatMap { ISO8601DateFormatter.anteFractional.date(from: $0) ?? ISO8601DateFormatter.antePlain.date(from: $0) }
        var title: String?
        for r in records where r["type"] as? String == "event_msg" {
            guard let p = r["payload"] as? [String: Any], p["type"] as? String == "user_message",
                  let text = p["message"] as? String, ClaudeSessionSource.isRealPrompt(text) else { continue }
            title = text; break
        }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created ?? Date()
        return PastSession(id: id, agent: .codex, title: ClaudeSessionSource.clean(title ?? "Codex session"), projectPath: cwd,
                           createdAt: created ?? modified, modifiedAt: modified, detail: source,
                           resumeCommand: AgentKind.codex.resumeCommand(sessionID: id))
    }
}
