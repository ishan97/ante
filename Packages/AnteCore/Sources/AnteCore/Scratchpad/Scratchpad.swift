// Packages/AnteCore/Sources/AnteCore/Scratchpad/Scratchpad.swift
import Foundation

/// A to-do item on the scratchpad.
public struct TodoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var text: String
    public var isDone: Bool
    public let createdAt: Date
    public var doneAt: Date?

    public init(id: UUID = UUID(), text: String, isDone: Bool = false, createdAt: Date = Date(), doneAt: Date? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
        self.doneAt = doneAt
    }
}

/// What the scratchpad holds: the to-do list and a free-text note. One per user.
public struct Scratchpad: Hashable, Codable, Sendable {
    public var items: [TodoItem]
    public var notes: String

    public init(items: [TodoItem] = [], notes: String = "") {
        self.items = items
        self.notes = notes
    }

    public var openItems: [TodoItem] { items.filter { !$0.isDone } }
    public var doneItems: [TodoItem] { items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) } }

    private enum CodingKeys: String, CodingKey { case items, notes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// Reads and writes the scratchpad file atomically (`0600`, like everything else under
/// Application Support).
public struct ScratchpadStore: Sendable {
    public let file: URL

    public init(paths: AppPaths) { self.file = paths.scratchpadFile }
    public init(file: URL) { self.file = file }

    public func load() -> Scratchpad {
        guard let data = try? Data(contentsOf: file),
              let pad = try? JSONDecoder.anteScratchpad.decode(Scratchpad.self, from: data) else { return Scratchpad() }
        return pad
    }

    public func save(_ pad: Scratchpad) throws {
        try AtomicFile.write(try JSONEncoder.anteScratchpad.encode(pad), to: file)
    }
}

extension JSONEncoder {
    static var anteScratchpad: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
extension JSONDecoder {
    static var anteScratchpad: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
