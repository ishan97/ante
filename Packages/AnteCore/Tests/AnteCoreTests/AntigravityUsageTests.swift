import XCTest
import SQLite3
@testable import AnteCore

final class AntigravityUsageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agy-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Protobuf by hand

    private func varint(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }
    private func number(_ field: Int, _ value: UInt64) -> [UInt8] { varint(UInt64(field << 3)) + varint(value) }
    private func message(_ field: Int, _ body: [UInt8]) -> [UInt8] { varint(UInt64(field << 3 | 2)) + varint(UInt64(body.count)) + body }

    /// A step's metadata the way Antigravity writes it (field numbers as observed).
    private func step(at seconds: UInt64, model: UInt64, input: UInt64, output: UInt64, cacheRead: UInt64 = 0, thinking: UInt64 = 0) -> [UInt8] {
        message(1, number(1, seconds) + number(2, 500_000_000)) + number(3, 2)
            + message(9, number(1, model) + number(2, input) + number(3, output) + (cacheRead > 0 ? number(5, cacheRead) : [])
                      + number(6, 24) + (thinking > 0 ? number(9, thinking) : []) + number(10, output - thinking))
            + number(11, model)
    }

    /// A generation record: settings first (field 3), then field 1 with the model id and name.
    private func generation(model: UInt64, name: String) -> [UInt8] {
        number(2, 1) + message(3, message(28, Array("\(name)-xhigh".utf8)) + message(5, Array(repeating: 0x41, count: 2000)))
            + message(1, number(3, model) + message(4, number(1, model) + number(2, 10)) + message(19, Array(name.utf8)))
    }

    private func makeConversation(_ id: String, in folder: URL, steps: [(Int, Int, [UInt8])], generations: [[UInt8]]) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(id).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in [
            "CREATE TABLE `steps` (`idx` integer,`step_type` integer NOT NULL DEFAULT 0,`status` integer NOT NULL DEFAULT 0,`metadata` blob,`step_payload` blob,PRIMARY KEY (`idx`))",
            "CREATE TABLE `gen_metadata` (`idx` integer,`data` blob,`size` integer NOT NULL DEFAULT 0,PRIMARY KEY (`idx`))",
        ] { XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK) }
        func insert(_ sql: String, _ rows: [(Int, Int, [UInt8])]) {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
            for (index, type, blob) in rows {
                sqlite3_reset(statement)
                sqlite3_bind_int(statement, 1, Int32(index))
                sqlite3_bind_int(statement, 2, Int32(type))
                _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(blob.count), nil) }
                XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            }
            sqlite3_finalize(statement)
        }
        insert("INSERT INTO steps (idx, step_type, metadata) VALUES (?, ?, ?)", steps)
        insert("INSERT INTO gen_metadata (idx, size, data) VALUES (?, ?, ?)", generations.enumerated().map { ($0.offset, $0.element.count, $0.element) })
        return url
    }

    // MARK: -

    func testStepsWithUsageBecomeRecordsNamedFromGenerations() throws {
        let folder = root.appendingPathComponent("antigravity-cli/conversations")
        let user = message(1, number(1, 1_794_850_491)) + number(3, 4)   // the prompt: no usage
        let url = try makeConversation("da3c1c9a-841d-4bd9-9604-f031ee1c87c8", in: folder, steps: [
            (0, 14, user),
            (1, 15, step(at: 1_794_850_499, model: 1418, input: 17_704, output: 55)),
            (2, 15, step(at: 1_794_851_024, model: 1418, input: 20_775, output: 429, cacheRead: 128_388, thinking: 219)),
            (3, 132, [0xFF, 0xFF, 0xFF]),   // not protobuf: skipped, not fatal
        ], generations: [generation(model: 1418, name: "gemini-4-argon-trial"), generation(model: 1418, name: "gemini-4-argon-trial")])

        var names: [Int: String] = [:]
        var after = -1
        let records = try XCTUnwrap(AntigravityUsage.records(database: url, names: &names, afterGeneration: &after))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.agent), [.antigravity, .antigravity])
        XCTAssertEqual(records.map(\.model), ["gemini-4-argon-trial", "gemini-4-argon-trial"])
        XCTAssertEqual(records[0].count, TokenCount(input: 17_704, output: 55))
        XCTAssertEqual(records[1].count, TokenCount(input: 20_775, output: 429, cacheRead: 128_388), "output already includes thinking")
        XCTAssertEqual(records[1].at.timeIntervalSince1970, 1_794_851_024.5, accuracy: 0.001)
        XCTAssertEqual(records.map(\.key), ["antigravity:da3c1c9a-841d-4bd9-9604-f031ee1c87c8:1", "antigravity:da3c1c9a-841d-4bd9-9604-f031ee1c87c8:2"])
        XCTAssertEqual(after, 0, "one generation was enough to name the model")
        XCTAssertEqual(names, [1418: "gemini-4-argon-trial"])
    }

    func testUnnamedModelKeepsItsId() throws {
        let url = try makeConversation("c1", in: root, steps: [(1, 15, step(at: 1_794_850_499, model: 77, input: 10, output: 5))], generations: [])
        var names: [Int: String] = [:]
        var after = -1
        XCTAssertEqual(try XCTUnwrap(AntigravityUsage.records(database: url, names: &names, afterGeneration: &after)).map(\.model), ["Antigravity model 77"])
        XCTAssertNil(AntigravityUsage.records(database: root.appendingPathComponent("missing.db"), names: &names, afterGeneration: &after),
                     "an unreadable conversation is not reported as empty")
    }

    func testLedgerCountsAntigravityOnceAcrossFoldersAndRereadsOnlyOnChange() async throws {
        let now = Date(timeIntervalSince1970: 1_794_900_000)
        let cli = root.appendingPathComponent("antigravity-cli/conversations")
        let app = root.appendingPathComponent("antigravity/conversations")
        let steps = [(1, 15, step(at: 1_794_850_499, model: 1535, input: 1000, output: 200))]
        _ = try makeConversation("same", in: cli, steps: steps, generations: [generation(model: 1535, name: "gemini-4-neon")])
        _ = try makeConversation("same", in: app, steps: steps, generations: [])
        let empty = root.appendingPathComponent("none")
        let ledger = TokenLedger(sources: .init(claudeProjects: empty, codexRoots: [], openCodeDatabase: empty.appendingPathComponent("x.db"),
                                                piSessions: empty, geminiTmp: empty, antigravityConversations: [cli, app]))
        let report = await ledger.report(now: now)
        let day = report.slice(.week)
        XCTAssertEqual(day.total, 1200, "the same conversation in two folders counts once")
        XCTAssertEqual(day.byAgent, [.init(agent: .antigravity, tokens: 1200)])
        XCTAssertEqual(day.byModel.map(\.name), ["gemini-4-neon"])
        let again = await ledger.report(now: now)
        XCTAssertEqual(again, report)
    }

    func testMalformedProtobufNeverCrashes() {
        let samples: [[UInt8]] = [[], [0x08], [0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F], [0x0A, 0x05, 0x01], [0x00],
                                  Array(repeating: 0xFF, count: 20), [0x4A, 0x02, 0x10], [0x0F]]
        for sample in samples {
            XCTAssertNil(AntigravityUsage.step(sample))
            XCTAssertNil(AntigravityUsage.generationModel(sample))
        }
        // A repeated field reads as its last value.
        XCTAssertEqual(Proto.varint(Proto.fields(([0x08, 0x01, 0x08, 0x02] as [UInt8])[...]) ?? [], 1), 2)
        XCTAssertNil(AntigravityUsage.bytes(hex: "ABC"))
        XCTAssertNil(AntigravityUsage.bytes(hex: "ZZ"))
        XCTAssertEqual(AntigravityUsage.bytes(hex: "0aFf"), [0x0A, 0xFF])
    }
}
