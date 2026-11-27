import Foundation

/// Token usage from Antigravity's own records. `agy` and the Antigravity app keep each
/// conversation in `<data folder>/conversations/<conversation id>.db` (SQLite). Every model call
/// is a row in `steps` whose `metadata` blob (protobuf) carries:
///
/// - field 1: when the step was created (`google.protobuf.Timestamp`)
/// - field 9: the call's usage: 1 model id, 2 fresh input, 3 output (thinking included; 9 is
///   thinking and 10 the reply), 4 cache writes, 5 cache reads
/// - field 11: the model id
///
/// The model id is a number; its name (`gemini-4-neon`) is only in the conversation's
/// `gen_metadata` rows (field 1 → 3 id, 19 name), which can be hundreds of kilobytes each, so they
/// are read one at a time and only until every id seen is named.
public enum AntigravityUsage {
    /// The usage in one conversation database. `names` maps model ids to names and is filled in
    /// from the database's generations when a step uses an id it does not know; `afterGeneration`
    /// is the last generation already looked at (so a growing conversation is not re-read).
    /// Nil when the steps could not be read (busy, or unreadable), so the caller does not remember
    /// that as the conversation's usage.
    static func records(database: URL, names: inout [Int: String], afterGeneration: inout Int) -> [TokenRecord]? {
        let conversation = database.deletingPathExtension().lastPathComponent
        var calls: [(index: Int, at: Date, model: Int?, count: TokenCount)] = []
        // A step's metadata is well under a kilobyte; anything far bigger is not one worth decoding.
        guard let rows = SQLiteReader.committedRows(database: database, sql: """
            SELECT idx, hex(metadata) FROM steps WHERE length(metadata) BETWEEN 1 AND \(maxStepMetadata) ORDER BY idx LIMIT 200000
            """) else { return nil }
        for row in rows {
            guard row.count >= 2, let index = row[0].flatMap({ Int($0) }), let bytes = row[1].flatMap(Self.bytes(hex:)),
                  let call = step(bytes) else { continue }
            calls.append((index, call.at, call.model, call.count))
        }
        var unnamed = Set(calls.compactMap(\.model)).subtracting(names.keys)
        // One generation at a time, and only a few per scan (the next scan carries on from there).
        var lookups = 0
        while !unnamed.isEmpty, lookups < maxGenerationLookups {
            lookups += 1
            guard let row = SQLiteReader.rows(database: database, sql: """
                SELECT idx, hex(data) FROM gen_metadata WHERE idx > \(afterGeneration) ORDER BY idx LIMIT 1
                """).first, row.count >= 2, let index = row[0].flatMap({ Int($0) }) else { break }
            afterGeneration = index
            if let bytes = row[1].flatMap(Self.bytes(hex:)), let model = generationModel(bytes) {
                names[model.id] = model.name
                unnamed.remove(model.id)
            }
        }
        return calls.map { call in
            TokenRecord(at: call.at, agent: .antigravity, model: call.model.map { names[$0] ?? "Antigravity model \($0)" } ?? "",
                        count: call.count, key: "antigravity:\(conversation):\(call.index)")
        }
    }

    /// A step that called a model: when, which model, and the tokens. Nil for any other step.
    static func step(_ bytes: [UInt8]) -> (at: Date, model: Int?, count: TokenCount)? {
        guard let fields = Proto.fields(bytes[...]),
              let usageBytes = Proto.bytes(fields, 9), let usage = Proto.fields(usageBytes),
              let createdBytes = Proto.bytes(fields, 1), let created = Proto.fields(createdBytes),
              let seconds = Proto.varint(created, 1), seconds > 0, seconds < 10_000_000_000 else { return nil }
        let nanos = min(Proto.varint(created, 2) ?? 0, 999_999_999)
        let count = TokenCount(input: Proto.count(usage, 2), output: Proto.count(usage, 3),
                               cacheRead: Proto.count(usage, 5), cacheWrite: Proto.count(usage, 4))
        guard count.total > 0 else { return nil }
        let model = (Proto.varint(fields, 11) ?? Proto.varint(usage, 1)).flatMap { $0 > 0 && $0 < 1_000_000 ? Int($0) : nil }
        return (Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9), model, count)
    }

    static let maxStepMetadata = 64 * 1024
    static let maxGenerationLookups = 20

    /// The model id and name a generation was made with.
    static func generationModel(_ bytes: [UInt8]) -> (id: Int, name: String)? {
        guard let top = Proto.fields(bytes[...]), let inner = Proto.bytes(top, 1), let fields = Proto.fields(inner),
              let id = Proto.varint(fields, 3), id > 0, id < 1_000_000,
              let nameBytes = Proto.bytes(fields, 19), nameBytes.count <= 100,
              let name = String(bytes: nameBytes, encoding: .utf8),
              !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "-._/".contains($0) }) else { return nil }
        return (Int(id), name)
    }

    /// `hex()` output from SQLite back to bytes.
    static func bytes(hex: String) -> [UInt8]? {
        let utf8 = Array(hex.utf8)
        guard utf8.count % 2 == 0 else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 65...70: return c - 55
            case 97...102: return c - 87
            default: return nil
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(utf8.count / 2)
        var i = 0
        while i < utf8.count {
            guard let high = nibble(utf8[i]), let low = nibble(utf8[i + 1]) else { return nil }
            out.append(high << 4 | low)
            i += 2
        }
        return out
    }
}

/// Just enough protobuf to read Antigravity's records: the fields of one message, without a
/// schema. Malformed input gives nil, never a crash or a read past the end.
enum Proto {
    enum Value {
        case varint(UInt64)
        case bytes(ArraySlice<UInt8>)
    }

    static func fields(_ bytes: ArraySlice<UInt8>) -> [(field: Int, value: Value)]? {
        var i = bytes.startIndex
        var out: [(field: Int, value: Value)] = []
        func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < bytes.endIndex {
                let byte = bytes[i]
                i += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < bytes.endIndex {
            guard let key = varint() else { return nil }
            let field = key >> 3
            guard field > 0, field < 1 << 29 else { return nil }
            switch key & 7 {
            case 0:
                guard let value = varint() else { return nil }
                out.append((Int(field), .varint(value)))
            case 1:
                guard bytes.endIndex - i >= 8 else { return nil }
                i += 8
            case 5:
                guard bytes.endIndex - i >= 4 else { return nil }
                i += 4
            case 2:
                guard let length = varint(), length <= UInt64(bytes.endIndex - i) else { return nil }
                let end = i + Int(length)
                out.append((Int(field), .bytes(bytes[i..<end])))
                i = end
            default:
                return nil
            }
        }
        return out
    }

    /// The field's value; the last one when it repeats, as protobuf reads it.
    static func varint(_ fields: [(field: Int, value: Value)], _ number: Int) -> UInt64? {
        for (field, value) in fields.reversed() where field == number { if case .varint(let v) = value { return v } }
        return nil
    }

    static func bytes(_ fields: [(field: Int, value: Value)], _ number: Int) -> ArraySlice<UInt8>? {
        for (field, value) in fields.reversed() where field == number { if case .bytes(let b) = value { return b } }
        return nil
    }

    /// A token count: zero when missing, never more than any one call could use.
    static func count(_ fields: [(field: Int, value: Value)], _ number: Int) -> Int {
        Int(min(varint(fields, number) ?? 0, UInt64(TokenCount.ceiling)))
    }
}
