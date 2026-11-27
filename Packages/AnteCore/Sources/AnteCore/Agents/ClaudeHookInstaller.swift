// Packages/AnteCore/Sources/AnteCore/Agents/ClaudeHookInstaller.swift
import Foundation

/// Adds/removes Ante's hook block in Claude Code's `settings.json`. The hook is one command that
/// appends Claude's own stdin JSON to a file Ante watches, prefixed with the pane it ran in
/// (`ANTE_PANE_ID`, set in each pane's shell) and the Claude process that ran it, tab-separated,
/// so Ante knows which pane's conversation changed — and not a `claude -p` running inside it. `SessionStart` is included so `/clear` and `/resume` report the new id at once.
public struct ClaudeHookInstaller: Sendable {
    public static let events = ["Notification", "Stop", "UserPromptSubmit", "SessionStart"]
    /// Ends the command; an install without it is from an older Ante and gets upgraded.
    public static let versionMarker = "# ante-hook-v4"

    public let settingsFile: URL
    public let eventFile: URL

    public init(settingsFile: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
                eventFile: URL) {
        self.settingsFile = settingsFile
        self.eventFile = eventFile
    }

    public var command: String {
        // `$PPID` is the agent process that ran the hook (Claude runs hooks as its direct
        // children). One `printf` per event, so concurrent hooks append whole lines (an append-mode write is
        // placed atomically) instead of a tag from one and a payload from another. The path is
        // single-quoted: nothing in it expands.
        #"line=$(cat); printf '%s\t%s\t%s\n' "${ANTE_PANE_ID:-}" "$PPID" "$line" >> \#(ShellQuote.quote(eventFile.path)) \#(Self.versionMarker)"#
    }

    /// True when the current version is on every event.
    public func isInstalled() -> Bool {
        guard let hooks = load()["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { event in
            ((hooks[event] as? [[String: Any]]) ?? []).contains { Self.isOurs($0, eventFile: eventFile) && Self.isCurrent($0) }
        }
    }

    /// True when any version of Ante's hook is on any event: the person turned it on at some point.
    public func hasAnyInstall() -> Bool {
        guard let hooks = load()["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { (($0 as? [[String: Any]]) ?? []).contains { Self.isOurs($0, eventFile: eventFile) } }
    }

    /// Brings an older install up to date in place: each of Ante's outdated entries becomes the
    /// current one, where it is. Events the person removed Ante's entry from stay without it; only
    /// `SessionStart`, which the first version didn't have, is added when upgrading from that one.
    /// Writes nothing when the hook is off or already current.
    public func upgradeIfInstalled() throws {
        var root = load()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        var changed = false
        var fromFirstVersion = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]],
                  groups.contains(where: { Self.isOurs($0, eventFile: eventFile) && !Self.isCurrent($0) }) else { continue }
            var updated: [[String: Any]] = []
            var placed = false
            for group in groups {
                guard Self.isOurs(group, eventFile: eventFile) else { updated.append(group); continue }
                if !Self.hasAnyMarker(group) { fromFirstVersion = true }
                if !placed { updated.append(currentGroup); placed = true }   // one of ours per event
            }
            hooks[event] = updated
            changed = true
        }
        if fromFirstVersion {
            let groups = hooks["SessionStart"] as? [[String: Any]] ?? []
            if !groups.contains(where: { Self.isOurs($0, eventFile: eventFile) }) { hooks["SessionStart"] = groups + [currentGroup] }
        }
        guard changed else { return }
        root["hooks"] = hooks
        if !FileManager.default.fileExists(atPath: eventFile.path) {
            try FileManager.default.createDirectory(at: eventFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(Data(), to: eventFile)
        }
        try save(root)
    }

    private var currentGroup: [String: Any] { ["matcher": "", "hooks": [["type": "command", "command": command]]] }

    /// Any versioned install carries `# ante-hook-v<n>`; the first version had no marker.
    static func hasAnyMarker(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("# ante-hook-v") == true }
    }

    /// Backs the file up, then appends our matcher group to each event (without disturbing others).
    public func install() throws {
        var root = load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { Self.isOurs($0, eventFile: eventFile) }
            groups.append(currentGroup)
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

    static func isCurrent(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.hasSuffix(versionMarker) == true }
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
        // Through a symlink (dotfiles repos link settings.json), never replacing the link itself.
        try AtomicFile.write(data, to: settingsFile.resolvingSymlinksInPath())   // 0600: the file can hold API keys under `env`
    }
}
