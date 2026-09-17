import XCTest
import AnteCore
@testable import AnteTerm

final class GoldenFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> [UInt8] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "bytes", subdirectory: "Fixtures"),
                                "missing fixture \(name)")
        return Array(try Data(contentsOf: url))
    }

    /// Runs the full pipeline over the bytes using the given chunk size.
    private func events(from bytes: [UInt8], chunkSize: Int) -> [SemanticEvent] {
        var scanner = OSCScanner()
        let parser = SemanticPromptParser()
        var out: [SemanticEvent] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + chunkSize, bytes.count)
            out += parser.parse(all: scanner.scan(bytes[index..<end]))
            index = end
        }
        return out
    }

    /// The sequence every shell must produce for `true; false; cd /tmp; exit`, ignoring cwd paths
    /// except the final one.
    private func assertBasicShape(_ events: [SemanticEvent], file: StaticString = #filePath, line: UInt = #line) {
        let withoutCwd = events.filter {
            if case .cwdChanged = $0 { return false }
            return true
        }
        XCTAssertEqual(withoutCwd, [
            .promptStarted,
            .commandStarted, .commandFinished(exitCode: 0),   // true
            .promptStarted,
            .commandStarted, .commandFinished(exitCode: 1),   // false
            .promptStarted,
            .commandStarted, .commandFinished(exitCode: 0),   // cd /tmp
            .promptStarted,
            .commandStarted,                                  // exit — no D, the shell is gone
        ], file: file, line: line)

        let cwds = events.compactMap { event -> URL? in
            if case let .cwdChanged(url) = event { return url }
            return nil
        }
        XCTAssertEqual(cwds.count, 4, "one cwd report per prompt", file: file, line: line)
        XCTAssertEqual(cwds.last?.path, "/tmp", file: file, line: line)
        XCTAssertEqual(Set(cwds.dropLast().map(\.path)).count, 1, "first three prompts share the start directory", file: file, line: line)
    }

    func testZshBasicShape() throws {
        let bytes = try fixture("zsh-basic")
        assertBasicShape(events(from: bytes, chunkSize: bytes.count))
    }

    func testBashBasicShape() throws {
        let bytes = try fixture("bash-basic")
        assertBasicShape(events(from: bytes, chunkSize: bytes.count))
    }

    func testChunkingDoesNotChangeEvents() throws {
        for name in ["zsh-basic", "bash-basic"] {
            let bytes = try fixture(name)
            let whole = events(from: bytes, chunkSize: bytes.count)
            for size in [1, 7, 64, 4096] {
                XCTAssertEqual(events(from: bytes, chunkSize: size), whole, "\(name) chunk \(size)")
            }
        }
    }

    func testEventOrderWithinAPromptCycle() throws {
        // D (finish) must come before the cwd report and the next A, for every cycle.
        let bytes = try fixture("zsh-basic")
        let all = events(from: bytes, chunkSize: bytes.count)
        var sawFinished = false
        for event in all {
            switch event {
            case .commandFinished: sawFinished = true
            case .cwdChanged:
                if sawFinished { sawFinished = false }
            case .promptStarted:
                XCTAssertFalse(sawFinished, "cwd must be reported between D and A")
            case .commandStarted, .notification: break
            }
        }
    }
}
