import Foundation

/// Antigravity CLI (`agy`) and the Antigravity app each keep a `conversation_summaries.db` in
/// their data folder (`~/.gemini/antigravity-cli`, `~/.gemini/antigravity`,
/// `~/.gemini/antigravity-ide`): one `conversation_summaries` row per conversation with its title
/// (or a preview of the first prompt), `workspace_uris` (a JSON list of `file://` URIs),
/// `last_modified_time`, and `app_data_dir`, the surface it belongs to. The CLI's index also lists
/// the app's conversations, so rows are merged by id. `agy --conversation <id>` resumes one from
/// its workspace folder.
public struct AntigravitySessionSource: Sendable {
    public let databases: [URL]
    /// Whether a conversation's folder is worth listing: it still exists and is not a temporary
    /// folder (scripts and tests run `agy` in throwaway folders). Injectable for tests.
    let keepsFolder: @Sendable (String) -> Bool

    public init(databases: [URL]? = nil, keepsFolder: (@Sendable (String) -> Bool)? = nil) {
        let gemini = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
        self.databases = databases ?? ["antigravity-cli", "antigravity", "antigravity-ide"].map {
            gemini.appendingPathComponent($0).appendingPathComponent("conversation_summaries.db")
        }
        self.keepsFolder = keepsFolder ?? Self.isLastingFolder
    }

    /// Top-level conversations with a folder to resume in, newest first.
    public func scan() -> [PastSession] {
        var newest: [String: PastSession] = [:]
        for database in databases {
            for row in SQLiteReader.rows(database: database, sql: Self.query(columns: Self.columns(of: database))) {
                guard row.count >= 7, let session = Self.session(row), keepsFolder(session.projectPath) else { continue }
                if let existing = newest[session.id], existing.modifiedAt >= session.modifiedAt { continue }
                newest[session.id] = session
            }
        }
        return newest.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The columns `conversation_summaries` has in this database (older versions lack some).
    static func columns(of database: URL) -> Set<String> {
        Set(SQLiteReader.rows(database: database, sql: "PRAGMA table_info(conversation_summaries)").compactMap { $0.count > 1 ? $0[1] : nil })
    }

    /// Top-level conversations with steps; a battle's losing side is left out (its winner stays).
    /// Filters on columns this database doesn't have are dropped rather than failing the query.
    static func query(columns: Set<String>) -> String {
        var filters = ["step_count > 0"]
        if columns.contains("nesting_depth") { filters.append("nesting_depth = 0") }
        if columns.contains("parent_conversation_id") { filters.append("parent_conversation_id = ''") }
        if columns.contains("winning_conversation_id") {
            filters.append("(winning_conversation_id = '' OR winning_conversation_id = conversation_id)")
        }
        let optional = { (name: String) in columns.contains(name) ? name : "''" }
        return """
            SELECT conversation_id, title, \(optional("preview")), last_modified_time, \(optional("last_user_input_time")),
                   workspace_uris, \(optional("app_data_dir"))
            FROM conversation_summaries WHERE \(filters.joined(separator: " AND "))
            ORDER BY last_modified_time DESC LIMIT 2000
            """
    }

    /// The folder exists and is not a temporary one.
    @Sendable static func isLastingFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        let resolved = (path as NSString).resolvingSymlinksInPath + "/"
        return !temporaryRoots.contains { resolved.hasPrefix($0) }
    }

    /// Where throwaway folders live, links resolved (`/tmp` is `/private/tmp`), each ending in `/`:
    /// `/tmp`, and the root of every user's temporary folders, three levels above this user's
    /// (`<root>/<xx>/<id>/T/`).
    static let temporaryRoots: [String] = [NSTemporaryDirectory(), "/tmp", temporaryFoldersRoot].map {
        let resolved = ($0 as NSString).resolvingSymlinksInPath
        return resolved.hasSuffix("/") ? resolved : resolved + "/"
    }

    static var temporaryFoldersRoot: String {
        URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
    }

    /// The conversation `agy --continue` would open in each folder: the CLI keeps the most recent
    /// one per workspace in `cache/last_conversations.json`.
    public static func lastConversations(cache: URL = FileManager.default.homeDirectoryForCurrentUser
                                            .appendingPathComponent(".gemini/antigravity-cli/cache/last_conversations.json")) -> [String: String] {
        guard let data = try? Data(contentsOf: cache),
              let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return [:] }
        return map
    }

    static func session(_ row: [String?]) -> PastSession? {
        guard let id = row[0], let resume = AgentKind.antigravity.resumeCommand(sessionID: id),
              let modified = row[3].flatMap(date(from:)),
              let folder = row[5].flatMap(firstFolder(in:)) else { return nil }
        let title = [row[1], row[2]].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        // Year 1 is Go's zero time: no prompt recorded.
        let prompted = row[4].flatMap(date(from:)).flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
        return PastSession(id: id, agent: .antigravity, title: ClaudeSessionSource.clean(title ?? "Untitled conversation"),
                           projectPath: folder, createdAt: min(prompted ?? modified, modified), modifiedAt: modified,
                           detail: surface(row[6]), resumeCommand: resume)
    }

    /// The caption for a conversation started outside the CLI.
    static func surface(_ appDataDir: String?) -> String? {
        switch appDataDir {
        case "antigravity": return "app"
        case "antigravity-ide": return "IDE"
        default: return nil
        }
    }

    /// The first local folder in a `workspace_uris` JSON list.
    static func firstFolder(in json: String) -> String? {
        guard let uris = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String] else { return nil }
        for uri in uris {
            guard let url = URL(string: uri), url.isFileURL, !url.path.isEmpty else { continue }
            return url.path
        }
        return nil
    }

    /// `2026-11-17 04:18:49.097822+00:00` (Go's SQLite time text), with any number of fraction
    /// digits or none.
    static func date(from text: String) -> Date? {
        var stamp = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        if let dot = stamp.firstIndex(of: ".") {
            let digits = stamp[stamp.index(after: dot)...].prefix { $0.isNumber }
            let kept = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            stamp.replaceSubrange(dot..<stamp.index(dot, offsetBy: digits.count + 1), with: "." + kept)
        }
        if stamp.hasSuffix("Z") == false, stamp.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) == nil { stamp += "Z" }
        return ISO8601DateFormatter.anteFractional.date(from: stamp) ?? ISO8601DateFormatter.antePlain.date(from: stamp)
    }
}

/// The Google account Antigravity CLI last signed in as. `agy` keeps its sign-in in the macOS
/// Keychain (shared with the Antigravity app) and has no status command, but every run logs
/// `applyAuthResult: email=<email>, authMethod=<method>, …` near its start, to
/// `~/.gemini/antigravity-cli/log/cli-YYYYMMDD_HHMMSS.log`. A sign-out is not logged, so this is
/// the account last seen, not a promise that it is still signed in.
public struct AntigravitySignIn: Equatable, Sendable {
    public let email: String
    /// `consumer` for a personal Google account; business and Cloud sign-ins say otherwise.
    public let method: String?
    /// When the run that logged it started (from the log's name).
    public let at: Date

    public init(email: String, method: String?, at: Date) {
        self.email = email
        self.method = method
        self.at = at
    }

    /// Runs looked at, newest first. A run that logged no sign-in (still starting, or signed out)
    /// falls back to the one before, but never to a sign-in from long ago.
    static let runsChecked = 5
    static let headBytes = 256 * 1024
    static let tailBytes: UInt64 = 1024 * 1024

    /// The newest run's sign-in. Nil when agy never signed in here.
    public static func read(logDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".gemini/antigravity-cli/log")) -> AntigravitySignIn? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        // `cli-YYYYMMDD_HHMMSS.log` sorts by time; the `cli.log` link points at one of them.
        let logs = files.filter { $0.lastPathComponent.hasPrefix("cli-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for log in logs.prefix(runsChecked) {
            guard let match = lastSignIn(in: read(log)) else { continue }
            let at = startTime(of: log) ?? (try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return AntigravitySignIn(email: match.email, method: match.method, at: at)
        }
        return nil
    }

    /// The head of the log (where a run signs in) and its tail (a sign-in later in a long run).
    static func read(_ log: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return Data() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        guard size > UInt64(headBytes) + tailBytes else { return (try? handle.readToEnd()) ?? Data() }
        var data = (try? handle.read(upToCount: headBytes)) ?? Data()
        data.append(0x0A)
        try? handle.seek(toOffset: size - tailBytes)
        data.append((try? handle.readToEnd()) ?? Data())
        return data
    }

    /// `cli-20261127_233334.log` → that local time.
    static func startTime(of log: URL) -> Date? {
        let stamp = log.deletingPathExtension().lastPathComponent.dropFirst("cli-".count)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.date(from: String(stamp))
    }

    static func lastSignIn(in data: Data) -> (email: String, method: String?)? {
        let text = String(decoding: data, as: UTF8.self)
        let pattern = try! NSRegularExpression(pattern: #"applyAuthResult: email=([^\s,]+@[^\s,]+), authMethod=([A-Za-z_-]*)"#)
        guard let match = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let email = Range(match.range(at: 1), in: text) else { return nil }
        let method = Range(match.range(at: 2), in: text).map { String(text[$0]) }
        return (String(text[email]), method.flatMap { $0.isEmpty ? nil : $0 })
    }
}
