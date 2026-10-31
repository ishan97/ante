import XCTest
@testable import AnteCore

/// Whatever is in the agents' logs (garbage, half-written lines, absurd numbers, the wrong
/// types), the ledger must never trap: a crash here takes the whole app down.
final class TokenLedgerFuzzTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-fuzz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var sources: TokenLedger.Sources {
        TokenLedger.Sources(claudeProjects: root.appendingPathComponent("claude"), codexRoots: [root.appendingPathComponent("codex")],
                            openCodeDatabase: root.appendingPathComponent("opencode.db"), piSessions: root.appendingPathComponent("pi"),
                            geminiTmp: root.appendingPathComponent("gemini"), codexHome: root.appendingPathComponent("codexhome"))
    }

    private func put(_ relative: String, _ data: Data) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Numbers chosen to trip overflow, sign and conversion bugs.
    private let numbers = ["0", "-1", "1", "9223372036854775807", "-9223372036854775808", "18446744073709551615", "1e308", "-1e308",
                           "1e999", "NaN", "\"12\"", "null", "true", "[]", "{}", "4.5", "999999999999", "1000000000"]

    private func usageLine(_ rng: inout SystemRandomNumberGenerator, at: String) -> String {
        func n() -> String { numbers.randomElement(using: &rng)! }
        switch Int.random(in: 0..<4, using: &rng) {
        case 0:
            return #"{"type":"assistant","timestamp":\#(at),"requestId":"r\#(n())","message":{"id":"m","model":\#(n()),"usage":{"input_tokens":\#(n()),"output_tokens":\#(n()),"cache_read_input_tokens":\#(n()),"cache_creation_input_tokens":\#(n())}}}"#
        case 1:
            return #"{"timestamp":\#(at),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(n()),"cached_input_tokens":\#(n()),"cache_write_input_tokens":\#(n()),"output_tokens":\#(n())},"last_token_usage":{"input_tokens":\#(n()),"cached_input_tokens":\#(n()),"output_tokens":\#(n())}}}}"#
        case 2:
            return #"{"timestamp":\#(at),"type":"turn_context","payload":{"model":\#(n())}}"#
        default:
            return #"{"type":"message","id":"p","timestamp":\#(at),"message":{"role":"assistant","model":"x","usage":{"input":\#(n()),"output":\#(n()),"cacheRead":\#(n()),"cacheWrite":\#(n())}}}"#
        }
    }

    func testHostileLogsNeverTrap() async throws {
        var rng = SystemRandomNumberGenerator()
        let now = Date()
        let stamps = ["\"\(ISO8601DateFormatter().string(from: now.addingTimeInterval(-60)))\"", "\"not a date\"", "1e300", "-5",
                      "\(Int64(now.timeIntervalSince1970 * 1000))", "null", "\"\(ISO8601DateFormatter().string(from: now.addingTimeInterval(86400 * 400)))\""]
        for round in 0..<6 {
            for (dir, ext) in [("claude/p", "jsonl"), ("codex/2026/10/31", "jsonl"), ("pi/s", "jsonl")] {
                var lines: [String] = []
                for _ in 0..<400 {
                    let line = usageLine(&rng, at: stamps.randomElement(using: &rng)!)
                    switch Int.random(in: 0..<6, using: &rng) {
                    case 0: lines.append(String(line.prefix(Int.random(in: 0...line.count, using: &rng))))   // half-written
                    case 1: lines.append(String((0..<Int.random(in: 0..<200, using: &rng)).map { _ in Character(UnicodeScalar(UInt8.random(in: 0...255, using: &rng))) }))
                    default: lines.append(line)
                    }
                }
                var data = Data(lines.joined(separator: "\n").utf8)
                data.append(contentsOf: (0..<Int.random(in: 0..<64, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })   // no final newline
                try put("\(dir)/f\(round).\(ext)", data)
            }
            // Gemini: one JSON document, sometimes broken.
            let geminiMessages = (0..<50).map { _ in
                #"{"id":"g","timestamp":\#(stamps.randomElement(using: &rng)!),"type":"gemini","model":"m","tokens":{"input":\#(numbers.randomElement(using: &rng)!),"output":\#(numbers.randomElement(using: &rng)!),"cached":\#(numbers.randomElement(using: &rng)!),"thoughts":\#(numbers.randomElement(using: &rng)!),"tool":\#(numbers.randomElement(using: &rng)!)}}"#
            }.joined(separator: ",")
            let gemini = #"{"sessionId":"s","messages":[\#(geminiMessages)]}"#
            try put("gemini/h/chats/session-\(round).json", Data((round % 2 == 0 ? gemini : String(gemini.dropLast(7))).utf8))
            let ledger = TokenLedger(sources: sources)
            let report = await ledger.report(now: now)
            // Every total stays a sane, non-negative number within the per-record ceiling's reach.
            for slice in report.slices {
                XCTAssertGreaterThanOrEqual(slice.total, 0)
                XCTAssertTrue(slice.byAgent.allSatisfy { $0.tokens >= 0 })
            }
            // A second scan reads appended garbage incrementally, without trapping either.
            let handle = try FileHandle(forWritingTo: root.appendingPathComponent("claude/p/f\(round).jsonl"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((0..<4096).map { _ in UInt8.random(in: 0...255, using: &rng) }))
            try handle.close()
            _ = await ledger.report(now: now)
        }
    }

    func testOneHugeLineIsSkippedNotHeld() async throws {
        // Longer than anything the ledger parses: skipped, and the usage after it still counts.
        let now = Date()
        let at = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        var data = Data(repeating: UInt8(ascii: "x"), count: TokenLedger.maxParsedLine + 10)
        data.append(Data("\n".utf8))
        data.append(Data((#"{"type":"assistant","timestamp":"\#(at)","requestId":"r","message":{"id":"m","model":"x","usage":{"input_tokens":5,"output_tokens":1}}}"# + "\n").utf8))
        try put("claude/p/big.jsonl", data)
        let report = await TokenLedger(sources: sources).report(now: now)
        XCTAssertEqual(report.slice(.day).total, 6)
    }
}
