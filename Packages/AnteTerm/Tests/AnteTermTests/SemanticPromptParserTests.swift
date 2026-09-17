import XCTest
import AnteCore
@testable import AnteTerm

final class SemanticPromptParserTests: XCTestCase {
    private let parser = SemanticPromptParser()

    private func osc(_ code: Int, _ payload: String) -> OSCSequence {
        OSCSequence(code: code, payload: Array(payload.utf8))
    }

    func testWorkingDirectoryFromAnotherHostIsIgnored() {
        XCTAssertNil(parser.parse(osc(7, "file://build-box.example.com/home/ci/repo")), "an ssh session's cwd, no such directory here")
        XCTAssertEqual(parser.parse(osc(7, "file://localhost/tmp")), .cwdChanged(URL(fileURLWithPath: "/tmp")))
        var buffer = [CChar](repeating: 0, count: 256); gethostname(&buffer, buffer.count)
        XCTAssertEqual(parser.parse(osc(7, "file://\(String(cString: buffer))/tmp")), .cwdChanged(URL(fileURLWithPath: "/tmp")))
    }

    func testNotificationButNotProgress() {
        XCTAssertEqual(parser.parse(osc(9, "Claude needs your permission")), .notification("Claude needs your permission"))
        XCTAssertNil(parser.parse(osc(9, "4;3;")), "ConEmu progress shares OSC 9")
        XCTAssertNil(parser.parse(osc(9, "4;0;")))
        XCTAssertNil(parser.parse(osc(9, "  ")))
    }

    func testPromptStart() {
        XCTAssertEqual(parser.parse(osc(133, "A")), .promptStarted)
    }

    func testPromptStartWithOptionsIsStillPromptStart() {
        XCTAssertEqual(parser.parse(osc(133, "A;k=i;aid=123")), .promptStarted)
    }

    func testInputStartIsIgnored() {
        XCTAssertNil(parser.parse(osc(133, "B")))
    }

    func testCommandStart() {
        XCTAssertEqual(parser.parse(osc(133, "C")), .commandStarted)
    }

    func testCommandFinishedWithExitCode() {
        XCTAssertEqual(parser.parse(osc(133, "D;0")), .commandFinished(exitCode: 0))
        XCTAssertEqual(parser.parse(osc(133, "D;130")), .commandFinished(exitCode: 130))
    }

    func testCommandFinishedWithoutExitCode() {
        XCTAssertEqual(parser.parse(osc(133, "D")), .commandFinished(exitCode: nil))
    }

    func testCommandFinishedWithGarbageExitCode() {
        XCTAssertEqual(parser.parse(osc(133, "D;abc")), .commandFinished(exitCode: nil))
    }

    func testCommandFinishedWithTrailingOptions() {
        XCTAssertEqual(parser.parse(osc(133, "D;1;aid=7")), .commandFinished(exitCode: 1))
    }

    func testUnknownActionIsIgnored() {
        XCTAssertNil(parser.parse(osc(133, "Z")))
        XCTAssertNil(parser.parse(osc(133, "")))
    }

    func testCwdFromFileURLWithHost() {
        XCTAssertEqual(parser.parse(osc(7, "file://localhost/Users/x/code")),
                       .cwdChanged(URL(fileURLWithPath: "/Users/x/code")), "localhost: taken at its word")
        XCTAssertEqual(parser.parse(osc(7, "file://mac.example.com/tmp")),
                       .cwdChanged(URL(fileURLWithPath: "/tmp")), "an unfamiliar host: accepted because the directory exists here")
    }

    func testCwdPercentDecodes() {
        XCTAssertEqual(parser.parse(osc(7, "file://localhost/tmp/a%20b/c%C3%A9")),
                       .cwdChanged(URL(fileURLWithPath: "/tmp/a b/cé")))
    }

    func testCwdWithoutHost() {
        XCTAssertEqual(parser.parse(osc(7, "file:///tmp")), .cwdChanged(URL(fileURLWithPath: "/tmp")))
    }

    func testCwdRejectsNonFileScheme() {
        XCTAssertNil(parser.parse(osc(7, "https://example.com/x")))
        XCTAssertNil(parser.parse(osc(7, "/just/a/path")))
        XCTAssertNil(parser.parse(osc(7, "")))
    }

    func testCwdRejectsInvalidUTF8() {
        XCTAssertNil(parser.parse(OSCSequence(code: 7, payload: [0x66, 0x69, 0x6C, 0x65, 0x3A, 0xFF])))
    }

    func testOtherCodesAreIgnored() {
        XCTAssertNil(parser.parse(osc(0, "window title")))
        XCTAssertNil(parser.parse(osc(1337, "CurrentDir=/tmp")))
    }

    func testParseAllKeepsOrderAndDropsNils() {
        let events = parser.parse(all: [osc(133, "A"), osc(0, "t"), osc(133, "C"), osc(133, "D;2")])
        XCTAssertEqual(events, [.promptStarted, .commandStarted, .commandFinished(exitCode: 2)])
    }
}
