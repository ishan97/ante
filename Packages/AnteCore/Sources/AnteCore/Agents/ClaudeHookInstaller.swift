// Packages/AnteCore/Sources/AnteCore/Agents/ClaudeHookInstaller.swift
import Foundation

/// Adds/removes Ante's hook block in Claude Code's `settings.json`. The hook is one command,
/// `cat >> "<event file>"`, so Claude's own stdin JSON lands in a file Ante watches.
public struct ClaudeHookInstaller: Sendable {
    public static let events = ["Notification", "Stop", "UserPromptSubmit"]

    public let settingsFile: URL
    public let eventFile: URL

    public init(settingsFile: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
                eventFile: URL) {
        self.settingsFile = settingsFile
        self.eventFile = eventFile
    }

    public var command: String { "cat >> \"\(eventFile.path)\"" }

    public func isInstalled() -> Bool {
        guard let hooks = load()["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { event in
            ((hooks[event] as? [[String: Any]]) ?? []).contains { Self.isOurs($0, eventFile: eventFile) }
        }
    }

    /// Backs the file up, then appends our matcher group to each event (without disturbing others).
    public func install() throws {
        var root = load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { Self.isOurs($0, eventFile: eventFile) }
            groups.append(["matcher": "", "hooks": [["type": "command", "command": command]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try FileManager.default.createDirectory(at: eventFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventFile.path) {
            try AtomicFile.write(Data(), to: eventFile)
        }
        try save(root)
    }

    /// Removes only our groups; leaves everything else exactly as it was.
    public func uninstall() throws {
        var root = load()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { Self.isOurs($0, eventFile: eventFile) }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try save(root)
        try? FileManager.default.removeItem(at: eventFile)   // the log of hook payloads goes with the hook
    }

    static func isOurs(_ group: [String: Any], eventFile: URL) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(eventFile.path) == true }
    }

    // MARK: - Transcript retention

    /// Claude Code's default: transcripts older than this are deleted on startup.
    public static let defaultRetentionDays = 30

    /// `cleanupPeriodDays` from settings.json, or Claude's default when unset.
    public func retentionDays() -> Int {
        (load()["cleanupPeriodDays"] as? Int) ?? Self.defaultRetentionDays
    }

    /// Writes `cleanupPeriodDays`; `nil` removes the key so Claude's default applies again.
    public func setRetentionDays(_ days: Int?) throws {
        var root = load()
        if let days { root["cleanupPeriodDays"] = max(1, days) } else { root["cleanupPeriodDays"] = nil }
        try save(root)
    }

    /// Every write backs the file up first; only the newest few backups are worth keeping.
    private func pruneBackups(keeping: Int) {
        let fm = FileManager.default
        let directory = settingsFile.deletingLastPathComponent()
        let prefix = settingsFile.lastPathComponent + ".ante-backup-"
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let backups = names.filter { $0.hasPrefix(prefix) }.sorted()
        for name in backups.dropLast(keeping) { try? fm.removeItem(at: directory.appendingPathComponent(name)) }
    }

    private func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return obj
    }

    private func save(_ root: [String: Any]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsFile.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            try? fm.copyItem(at: settingsFile, to: settingsFile.appendingPathExtension("ante-backup-\(stamp)"))
            pruneBackups(keeping: 5)
        } else {
            try fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try AtomicFile.write(data, to: settingsFile)   // 0600: the file can hold API keys under `env`
    }
}
