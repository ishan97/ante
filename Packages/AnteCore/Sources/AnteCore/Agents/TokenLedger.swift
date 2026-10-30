// Packages/AnteCore/Sources/AnteCore/Agents/TokenLedger.swift
import Foundation

/// Adds up the tokens every agent on this Mac has used, from the agents' own logs: Claude Code
/// transcripts, Codex rollouts, OpenCode's database, Pi sessions and Gemini CLI chats. Read only;
/// nothing leaves the machine.
///
/// Transcripts run to gigabytes, so each file is read once and remembered: an append-only log
/// that grew is read from where the last scan stopped, an unchanged one is not opened at all,
/// and only lines that can carry usage are decoded.
public actor TokenLedger {
    public struct Sources: Sendable {
        public var claudeProjects: URL
        public var codexRoots: [URL]
        public var openCodeDatabase: URL
        public var piSessions: URL
        public var geminiTmp: URL

        public init(claudeProjects: URL, codexRoots: [URL], openCodeDatabase: URL, piSessions: URL, geminiTmp: URL) {
            self.claudeProjects = claudeProjects
            self.codexRoots = codexRoots
            self.openCodeDatabase = openCodeDatabase
            self.piSessions = piSessions
            self.geminiTmp = geminiTmp
        }

        public static var `default`: Sources {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Sources(claudeProjects: home.appendingPathComponent(".claude/projects"),
                           codexRoots: [home.appendingPathComponent(".codex/sessions"), home.appendingPathComponent(".codex/archived_sessions")],
                           openCodeDatabase: home.appendingPathComponent(".local/share/opencode/opencode.db"),
                           piSessions: home.appendingPathComponent(".pi/agent/sessions"),
                           geminiTmp: home.appendingPathComponent(".gemini/tmp"))
        }
    }

    enum Format: Sendable { case claude, codex, pi, gemini }

    /// What one file contributed, and enough to carry on reading it later.
    struct FileEntry: Sendable {
        var fileNumber: Int
        var size: UInt64
        var modified: Date
        /// Bytes consumed so far: always the end of a complete line.
        var offset: UInt64
        var records: [TokenRecord]
        var codex = CodexState()
    }

    /// Codex logs a running total per session; each turn is the difference from the last one.
    struct CodexState: Sendable {
        var previous: TokenCount?
        var previousRawTotal = 0
        var model = ""
    }

    private let sources: Sources
    private var files: [String: FileEntry] = [:]

    public init(sources: Sources = .default) {
        self.sources = sources
    }

    /// Scans every source (incrementally) and adds up the last year.
    public func report(now: Date = Date(), calendar: Calendar = .current) -> TokenUsageReport {
        let horizon = TokenUsageReport.Window.year.start(before: now, calendar: calendar)
        var live = Set<String>()
        var records: [TokenRecord] = []
        let jsonl: [(URL, Format)] = [(sources.claudeProjects, .claude), (sources.piSessions, .pi)] + sources.codexRoots.map { ($0, .codex) }
        for (root, format) in jsonl {
            for file in Self.files(under: root, extension: "jsonl", modifiedAfter: horizon) {
                live.insert(file.path)
                records += read(file, format: format)
            }
        }
        for file in Self.files(under: sources.geminiTmp, extension: "json", modifiedAfter: horizon)
        where file.lastPathComponent.hasPrefix("session-") && file.deletingLastPathComponent().lastPathComponent == "chats" {
            live.insert(file.path)
            records += read(file, format: .gemini)
        }
        // Files that were deleted, or aged out of the year, are forgotten.
        files = files.filter { live.contains($0.key) }
        records += Self.openCode(database: sources.openCodeDatabase, since: horizon)
        return TokenUsageReport.build(records: records.filter { $0.at > horizon }, now: now, calendar: calendar)
    }

    // MARK: - Files

    private static func files(under root: URL, extension ext: String, modifiedAfter horizon: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        // The enumerator does not descend into symlinked folders, so nothing outside the
        // agent's own directory is read.
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == ext {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified > horizon else { continue }
            out.append(file)
        }
        return out
    }

    private func read(_ file: URL, format: Format) -> [TokenRecord] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return [] }
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? 0
        if let cached = files[file.path], cached.fileNumber == fileNumber {
            if cached.size == size, cached.modified == modified { return cached.records }
            // An append-only log that only grew: read the new lines.
            if format != .gemini, size >= cached.offset {
                var entry = cached
                entry.size = size
                entry.modified = modified
                entry.offset = Self.scanLines(of: file, from: cached.offset, format: format, state: &entry.codex) { entry.records.append($0) }
                files[file.path] = entry
                return entry.records
            }
        }
        var entry = FileEntry(fileNumber: fileNumber, size: size, modified: modified, offset: 0, records: [])
        if format == .gemini {
            entry.records = Self.gemini(file, size: size)
            entry.offset = size
        } else {
            entry.offset = Self.scanLines(of: file, from: 0, format: format, state: &entry.codex) { entry.records.append($0) }
        }
        files[file.path] = entry
        return entry.records
    }

    /// Reads complete lines from `offset` and decodes those that can carry usage. Returns the
    /// offset after the last complete line; a half-written last line is left for next time.
    static func scanLines(of file: URL, from offset: UInt64, format: Format, state: inout CodexState,
                          emit: (TokenRecord) -> Void) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }
        // A line is decoded when it contains every needle of any one group. Agents write compact
        // JSON, so a prompt that merely mentions "usage" is not parsed for nothing.
        let groups: [[[UInt8]]]
        switch format {
        case .claude: groups = [[Array(#""type":"assistant""#.utf8), Array(#""usage""#.utf8)]]
        case .pi: groups = [[Array(#""role":"assistant""#.utf8), Array(#""usage""#.utf8)]]
        case .codex: groups = [[Array(#""token_count""#.utf8)], [Array(#""turn_context""#.utf8)]]
        case .gemini: return offset
        }
        var consumed = offset
        var buffer = Data()
        while true {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                var cursor = 0
                while cursor < raw.count, let found = memchr(base + cursor, 0x0A, raw.count - cursor) {
                    let end = base.distance(to: UnsafeRawPointer(found))
                    let line = UnsafeRawBufferPointer(rebasing: raw[cursor..<end])
                    if line.count <= maxParsedLine, groups.contains(where: { $0.allSatisfy { contains(line, $0) } }),
                       let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] {
                        decode(object, format: format, state: &state, emit: emit)
                    }
                    cursor = end + 1
                }
                lineStart = buffer.startIndex + cursor
            }
            consumed += UInt64(lineStart - buffer.startIndex)
            buffer.removeSubrange(buffer.startIndex..<lineStart)
            // A line longer than anything an agent writes is not worth holding in memory: skip it.
            if buffer.count > maxLine {
                guard let rest = skipLine(handle) else { break }
                consumed += UInt64(buffer.count) + rest
                buffer.removeAll()
            }
        }
        return consumed
    }

    static let chunkSize = 4 * 1024 * 1024
    /// Lines with usage are a few kilobytes; transcripts can carry pasted images far larger.
    static let maxLine = 64 * 1024 * 1024
    /// Lines with usage are a few kilobytes; anything bigger is a pasted blob, not worth decoding.
    static let maxParsedLine = 8 * 1024 * 1024

    /// Reads up to and including the next newline; returns how many bytes that was, or nil at EOF.
    private static func skipLine(_ handle: FileHandle) -> UInt64? {
        var skipped: UInt64 = 0
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                let used = newline - chunk.startIndex + 1
                skipped += UInt64(used)
                if let here = try? handle.offset() { try? handle.seek(toOffset: here - UInt64(chunk.count - used)) }
                return skipped
            }
            skipped += UInt64(chunk.count)
        }
        return nil
    }

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = haystack.baseAddress, haystack.count >= needle.count else { return false }
        return needle.withUnsafeBytes { memmem(base, haystack.count, $0.baseAddress, needle.count) != nil }
    }

    // MARK: - Formats

    static func decode(_ r: [String: Any], format: Format, state: inout CodexState, emit: (TokenRecord) -> Void) {
        switch format {
        case .claude:
            // {"type":"assistant","timestamp":"…","requestId":"req_…","message":{"id":"msg_…","model":"…","usage":{…}}}
            guard r["type"] as? String == "assistant", let message = r["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any], let at = date(r["timestamp"]) else { return }
            let count = TokenCount(input: TokenCount.field(usage["input_tokens"]), output: TokenCount.field(usage["output_tokens"]),
                                   cacheRead: TokenCount.field(usage["cache_read_input_tokens"]),
                                   cacheWrite: TokenCount.field(usage["cache_creation_input_tokens"]))
            guard count.total > 0 else { return }
            let id = message["id"] as? String
            let key = id.map { "claude:\($0):\(r["requestId"] as? String ?? "")" }
            emit(TokenRecord(at: at, agent: .claude, model: message["model"] as? String ?? "", count: count, key: key))

        case .codex:
            guard let payload = r["payload"] as? [String: Any] else { return }
            if r["type"] as? String == "turn_context" {
                if let model = payload["model"] as? String { state.model = model }
                return
            }
            // {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{…},"last_token_usage":{…}}}}
            guard r["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any], let at = date(r["timestamp"]) else { return }
            guard let total = info["total_token_usage"] as? [String: Any] else { return }
            let (running, rawTotal) = codexCount(total)
            defer { state.previous = running; state.previousRawTotal = rawTotal }
            // The running total is repeated when nothing new happened; only growth is usage.
            var turn: TokenCount
            if let previous = state.previous, rawTotal >= state.previousRawTotal,
               running.input >= previous.input, running.output >= previous.output,
               running.cacheRead >= previous.cacheRead, running.cacheWrite >= previous.cacheWrite {
                turn = TokenCount(input: running.input - previous.input, output: running.output - previous.output,
                                  cacheRead: running.cacheRead - previous.cacheRead, cacheWrite: running.cacheWrite - previous.cacheWrite)
            } else if state.previous == nil {
                turn = running
            } else {
                // The running total went backwards (a new context): trust the turn's own figure.
                turn = (info["last_token_usage"] as? [String: Any]).map { codexCount($0).0 } ?? .zero
            }
            guard turn.total > 0 else { return }
            emit(TokenRecord(at: at, agent: .codex, model: state.model, count: turn))

        case .pi:
            // {"type":"message","id":"…","timestamp":"…","message":{"role":"assistant","model":"…","usage":{"input":…,"output":…,"cacheRead":…,"cacheWrite":…}}}
            guard r["type"] as? String == "message", let message = r["message"] as? [String: Any],
                  message["role"] as? String == "assistant", let usage = message["usage"] as? [String: Any],
                  let at = date(r["timestamp"]) ?? date(message["timestamp"]) else { return }
            let count = TokenCount(input: TokenCount.field(usage["input"]), output: TokenCount.field(usage["output"]),
                                   cacheRead: TokenCount.field(usage["cacheRead"]), cacheWrite: TokenCount.field(usage["cacheWrite"]))
            guard count.total > 0 else { return }
            emit(TokenRecord(at: at, agent: .pi, model: message["model"] as? String ?? "", count: count,
                             key: (r["id"] as? String).map { "pi:\($0)" }))

        case .gemini:
            return
        }
    }

    /// Codex's `input_tokens` includes the cached part; Ante counts fresh input and cache apart.
    private static func codexCount(_ usage: [String: Any]) -> (TokenCount, Int) {
        let input = TokenCount.field(usage["input_tokens"])
        let cached = TokenCount.field(usage["cached_input_tokens"])
        let written = TokenCount.field(usage["cache_write_input_tokens"])
        let output = TokenCount.field(usage["output_tokens"])
        let count = TokenCount(input: max(0, input - cached - written), output: output, cacheRead: min(cached, input), cacheWrite: min(written, max(0, input - cached)))
        return (count, input + output)
    }

    /// Gemini CLI rewrites one JSON document per chat:
    /// `{"sessionId":…,"messages":[{"id":…,"timestamp":…,"type":"gemini","model":…,"tokens":{"input":…,"output":…,"cached":…,"thoughts":…,"tool":…}}]}`.
    static func gemini(_ file: URL, size: UInt64) -> [TokenRecord] {
        guard size <= UInt64(maxLine), let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]] else { return [] }
        let session = object["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent
        return messages.compactMap { m in
            guard let tokens = m["tokens"] as? [String: Any], let at = date(m["timestamp"]) else { return nil }
            let input = TokenCount.field(tokens["input"]), cached = TokenCount.field(tokens["cached"])
            let count = TokenCount(input: max(0, input - cached) + TokenCount.field(tokens["tool"]),
                                   output: TokenCount.field(tokens["output"]) + TokenCount.field(tokens["thoughts"]),
                                   cacheRead: min(cached, input))
            guard count.total > 0 else { return nil }
            return TokenRecord(at: at, agent: .gemini, model: m["model"] as? String ?? "", count: count,
                               key: (m["id"] as? String).map { "gemini:\(session):\($0)" })
        }
    }

    /// OpenCode keeps a `message` row per turn with `{"role":"assistant","modelID":…,"tokens":{"input":…,"output":…,"reasoning":…,"cache":{"read":…,"write":…}}}`.
    static func openCode(database: URL, since horizon: Date) -> [TokenRecord] {
        // The cutoff is a number Ante computed, never text from a file.
        let since = Int64(horizon.timeIntervalSince1970 * 1000)
        return SQLiteReader.rows(database: database, sql: """
            SELECT time_created, json_extract(data, '$.modelID'), json_extract(data, '$.tokens.input'),
                   json_extract(data, '$.tokens.output'), json_extract(data, '$.tokens.reasoning'),
                   json_extract(data, '$.tokens.cache.read'), json_extract(data, '$.tokens.cache.write')
            FROM message WHERE time_created > \(since) AND json_valid(data)
              AND json_extract(data, '$.role') = 'assistant' AND json_type(data, '$.tokens') = 'object'
            LIMIT 1000000
            """).compactMap { row in
            guard row.count >= 7, let ms = row[0].flatMap(Double.init) else { return nil }
            func n(_ i: Int) -> Int { TokenCount.field(row[i].flatMap(Double.init).map(NSNumber.init(value:))) }
            let count = TokenCount(input: n(2), output: n(3) + n(4), cacheRead: n(5), cacheWrite: n(6))
            guard count.total > 0 else { return nil }
            return TokenRecord(at: Date(timeIntervalSince1970: ms / 1000), agent: .opencode, model: row[1] ?? "", count: count)
        }
    }

    /// ISO 8601 strings (with or without fractions) and epoch milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let s = value as? String {
            return ISO8601DateFormatter.anteFractional.date(from: s) ?? ISO8601DateFormatter.antePlain.date(from: s)
        }
        if let n = value as? NSNumber, n.doubleValue > 1e11, n.doubleValue.isFinite {
            return Date(timeIntervalSince1970: n.doubleValue / 1000)
        }
        return nil
    }
}
