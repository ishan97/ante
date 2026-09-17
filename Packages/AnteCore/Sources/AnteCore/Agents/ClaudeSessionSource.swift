// Packages/AnteCore/Sources/AnteCore/Agents/ClaudeSessionSource.swift
import Foundation

/// Claude Code keeps one `<session>.jsonl` per conversation under `~/.claude/projects/<slug>/`.
/// `sessions-index.json` exists in some project folders but is incomplete, so files are the truth
/// and the index only supplies a nicer title when it has one.
public struct ClaudeSessionSource: Sendable {
    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    public func scan() -> [PastSession] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [PastSession] = []
        for project in projects where (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let index = loadIndex(project.appendingPathComponent("sessions-index.json"))
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                // `agent-<id>.jsonl` are subagent transcripts (older layouts put them beside the
                // session); they belong to a parent session, not to the list.
                if file.deletingPathExtension().lastPathComponent.hasPrefix("agent-") { continue }
                if let session = parse(file: file, index: index) { out.append(session) }
            }
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    struct IndexEntry { let summary: String?; let firstPrompt: String? }

    private func loadIndex(_ url: URL) -> [String: IndexEntry] {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = obj["entries"] as? [[String: Any]] else { return [:] }
        var out: [String: IndexEntry] = [:]
        for e in entries {
            guard let id = e["sessionId"] as? String else { continue }
            out[id] = IndexEntry(summary: e["summary"] as? String, firstPrompt: e["firstPrompt"] as? String)
        }
        return out
    }

    func parse(file: URL, index: [String: IndexEntry]) -> PastSession? {
        let records = JSONLines.head(of: file)
        let sessionID = file.deletingPathExtension().lastPathComponent
        var cwd: String?
        var firstUserAt: Date?
        var promptAt: Date?
        var title: String?
        var summary: String?
        for r in records {
            if r["isSidechain"] as? Bool == true { return nil }   // a fork run for the parent, not a session of its own
            if r["type"] as? String == "summary", let s = r["summary"] as? String { summary = s }
            guard r["type"] as? String == "user", r["isMeta"] as? Bool != true else { continue }
            if cwd == nil { cwd = r["cwd"] as? String }
            let stamp = (r["timestamp"] as? String).flatMap { ISO8601DateFormatter.anteFractional.date(from: $0) ?? ISO8601DateFormatter.antePlain.date(from: $0) }
            if firstUserAt == nil { firstUserAt = stamp }
            if title == nil, let text = Self.userText(r["message"]), Self.isRealPrompt(text) {
                title = text
                promptAt = stamp
            }
            if title != nil, cwd != nil { break }
        }
        guard let cwd else { return nil }
        // "Created" is when the person first typed something, not when a tool result landed.
        let created = promptAt ?? firstUserAt
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created ?? Date()
        let entry = index[sessionID]
        let finalTitle = Self.clean(summary ?? entry?.summary ?? title ?? entry?.firstPrompt ?? "Untitled session")
        return PastSession(id: sessionID, agent: .claude, title: finalTitle, projectPath: cwd,
                           createdAt: created ?? modified, modifiedAt: modified, detail: nil,
                           resumeCommand: AgentKind.claude.resumeCommand(sessionID: sessionID))
    }

    static func userText(_ message: Any?) -> String? {
        guard let m = message as? [String: Any] else { return nil }
        if let s = m["content"] as? String { return s }
        if let parts = m["content"] as? [[String: Any]] {
            for p in parts where p["type"] as? String == "text" { if let t = p["text"] as? String { return t } }
        }
        return nil
    }

    static func isRealPrompt(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.hasPrefix("<") && t != "tool_result"
    }

    static func clean(_ text: String) -> String {
        let printable = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == " " || $0 == "\n" || $0 == "\t" })
        let oneLine = printable.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return oneLine.count > 120 ? String(oneLine.prefix(117)) + "…" : oneLine
    }
}

extension ISO8601DateFormatter {
    // Only ever used from the scanner's own thread; never shared across tasks.
    nonisolated(unsafe) static let anteFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let antePlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
