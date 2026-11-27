// Packages/AnteCore/Sources/AnteCore/Agents/HookEventWatcher.swift
import Foundation

/// One line appended by an agent hook (Claude's stdin JSON), reduced to what the board needs.
public struct HookEvent: Equatable, Sendable {
    public enum Meaning: Equatable, Sendable { case waiting(String), working, other }
    public let agent: AgentKind
    public let sessionID: String?
    public let cwd: String?
    public let event: String
    public let meaning: Meaning
    public let at: Date
    /// The pane the agent runs in (`ANTE_PANE_ID`), when the hook line carried one.
    public var paneID: String?
    /// The agent process the hook ran under (the hook shell's `$PPID`), when the line carried it.
    /// A `claude -p` started inside a pane inherits the pane's id but not this, so it tells the
    /// pane's own agent apart from anything that agent runs.
    public var processID: Int32?

    public init(agent: AgentKind, sessionID: String?, cwd: String?, event: String, meaning: Meaning, at: Date, paneID: String? = nil,
                processID: Int32? = nil) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.event = event
        self.meaning = meaning
        self.at = at
        self.paneID = paneID
        self.processID = processID
    }

    /// The hook log's lines: `<pane id>\t<agent pid>\t<json>` (current hook), `<pane id>\t<json>`
    /// (earlier) or plain `<json>` (oldest). JSON never holds a raw tab, so tabs split the fields
    /// exactly. A line of any other shape (two writers' bytes interleaved, a stray tab) is dropped
    /// rather than credited to the wrong pane or process.
    public static func parse(_ data: Data, at: Date = Date()) -> [HookEvent] {
        data.split(separator: 0x0A).compactMap { line -> HookEvent? in
            let fields = line.split(separator: 0x09, omittingEmptySubsequences: false)
            guard fields.count <= 3, let json = fields.last, json.first == 0x7B else { return nil }
            var pane: String?
            var pid: Int32?
            if fields.count >= 2 {
                let tag = fields[0]
                guard tag.count <= 64, tag.allSatisfy(isPaneIDByte) else { return nil }
                pane = tag.isEmpty ? nil : String(decoding: tag, as: UTF8.self)
            }
            if fields.count == 3 {
                let digits = fields[1]
                guard digits.count <= 10, digits.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
                pid = digits.isEmpty ? nil : Int32(String(decoding: digits, as: UTF8.self))
            }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(json))) as? [String: Any],
                  var event = fromClaude(obj, at: at) else { return nil }
            event.paneID = pane
            event.processID = pid
            return event
        }
    }

    private static func isPaneIDByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2D
    }

    public static func fromClaude(_ obj: [String: Any], at: Date = Date()) -> HookEvent? {
        guard let name = obj["hook_event_name"] as? String else { return nil }
        let meaning: Meaning
        switch name {
        case "Notification":
            let type = obj["notification_type"] as? String ?? "notification"
            // Shown on a card: keep it one clean line of sane length.
            let message = (obj["message"] as? String).map { String(String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(200)) }
            meaning = .waiting(message.flatMap { $0.isEmpty ? nil : $0 } ?? type)
        case "Stop": meaning = .waiting("finished its turn")
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": meaning = .working
        default: meaning = .other
        }
        return HookEvent(agent: .claude, sessionID: obj["session_id"] as? String, cwd: obj["cwd"] as? String,
                         event: name, meaning: meaning, at: at)
    }
}

/// Tails the append-only JSONL file the hooks write to (`cat >>`) and delivers new events on the
/// main queue. Watches the file's inode — an append changes no directory entry — and the
/// directory, to re-arm if the file is replaced. Once every line has been read and the file has
/// grown past `truncateAfterBytes`, it is emptied: the hooks' payloads carry full prompts and
/// there is no reason to keep them.
@MainActor
public final class HookEventWatcher {
    public static let truncateAfterBytes: UInt64 = 256 * 1024

    private let file: URL
    private let onEvents: @MainActor ([HookEvent]) -> Void
    private var offset: UInt64 = 0
    private var source: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    public init(file: URL, onEvents: @escaping @MainActor ([HookEvent]) -> Void) {
        self.file = file
        self.onEvents = onEvents
    }

    public func start() {
        stop()
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) { try? AtomicFile.write(Data(), to: file) }
        offset = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0   // start at the end
        fd = open(file.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.drain(); self?.armFileWatch() }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
        armFileWatch()
    }

    public func stop() {
        source?.cancel(); source = nil; fd = -1
        fileSource?.cancel(); fileSource = nil
    }

    private func armFileWatch() {
        fileSource?.cancel(); fileSource = nil
        let ffd = open(file.path, O_EVTONLY)
        guard ffd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: ffd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(ffd) }
        src.resume()
        fileSource = src
    }

    /// Reads whatever was appended since the last call. Public so tests (and a manual refresh) can call it.
    public func drain() {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }   // truncated / rotated
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = size
        if size > Self.truncateAfterBytes, let writer = try? FileHandle(forWritingTo: file) {
            // Everything up to `size` has been read; a hook appending in this instant would be
            // lost, which the next prompt corrects. Better than an unbounded log of prompts.
            try? writer.truncate(atOffset: 0)
            try? writer.close()
            offset = 0
        }
        let events = HookEvent.parse(data)
        if !events.isEmpty { onEvents(events) }
    }
}
