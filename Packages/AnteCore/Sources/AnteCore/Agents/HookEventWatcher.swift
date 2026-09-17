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

    public init(agent: AgentKind, sessionID: String?, cwd: String?, event: String, meaning: Meaning, at: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.event = event
        self.meaning = meaning
        self.at = at
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
        let events = JSONLines.parse(data).compactMap { HookEvent.fromClaude($0) }
        if !events.isEmpty { onEvents(events) }
    }
}
