import XCTest
@testable import AnteTerm

final class OSCScannerTests: XCTestCase {
    private func bytes(_ s: String) -> ArraySlice<UInt8> { ArraySlice(Array(s.utf8)) }

    func testBelTerminatedSequence() {
        var scanner = OSCScanner()
        let out = scanner.scan(bytes("hello\u{1b}]133;A\u{07}world"))
        XCTAssertEqual(out, [OSCSequence(code: 133, payload: Array("A".utf8))])
    }

    func testStTerminatedSequence() {
        var scanner = OSCScanner()
        let out = scanner.scan(bytes("\u{1b}]7;file://host/tmp\u{1b}\\"))
        XCTAssertEqual(out, [OSCSequence(code: 7, payload: Array("file://host/tmp".utf8))])
    }

    func testSequenceSplitAcrossChunksIsReassembled() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]13")), [])
        XCTAssertEqual(scanner.scan(bytes("3;D;")), [])
        XCTAssertEqual(scanner.scan(bytes("42\u{07}")), [OSCSequence(code: 133, payload: Array("D;42".utf8))])
    }

    func testSplitBetweenEscAndBracket() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}")), [])
        XCTAssertEqual(scanner.scan(bytes("]133;C\u{07}")), [OSCSequence(code: 133, payload: Array("C".utf8))])
    }

    func testSplitBetweenEscAndBackslashTerminator() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]133;A\u{1b}")), [])
        XCTAssertEqual(scanner.scan(bytes("\\")), [OSCSequence(code: 133, payload: Array("A".utf8))])
    }

    func testMultipleSequencesInOneChunk() {
        var scanner = OSCScanner()
        let out = scanner.scan(bytes("\u{1b}]133;A\u{07}$ \u{1b}]133;B\u{07}"))
        XCTAssertEqual(out.map(\.code), [133, 133])
        XCTAssertEqual(out.map { String(decoding: $0.payload, as: UTF8.self) }, ["A", "B"])
    }

    func testNonOscEscapesAreIgnored() {
        var scanner = OSCScanner()
        let out = scanner.scan(bytes("\u{1b}[31mred\u{1b}[0m\u{1b}]133;A\u{07}"))
        XCTAssertEqual(out.map(\.code), [133])
    }

    func testNewlineInsideOscAbortsIt() {
        var scanner = OSCScanner()
        let out = scanner.scan(bytes("\u{1b}]133;A\noops\u{07}\u{1b}]133;C\u{07}"))
        XCTAssertEqual(out, [OSCSequence(code: 133, payload: Array("C".utf8))])
    }

    func testPayloadWithoutSemicolon() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]104\u{07}")), [OSCSequence(code: 104, payload: [])])
    }

    func testNonNumericCodeIsDropped() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]x;y\u{07}")), [])
    }

    func testEmptyPayloadAfterSemicolon() {
        var scanner = OSCScanner()
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]0;\u{07}")), [OSCSequence(code: 0, payload: [])])
    }

    func testOversizedPayloadIsDroppedAndScannerRecovers() {
        var scanner = OSCScanner()
        var big = Array("\u{1b}]133;".utf8)
        big += [UInt8](repeating: UInt8(ascii: "x"), count: OSCScanner.maxPayloadBytes + 10)
        big += [0x07]
        XCTAssertEqual(scanner.scan(ArraySlice(big)), [])
        XCTAssertEqual(scanner.scan(bytes("\u{1b}]133;A\u{07}")), [OSCSequence(code: 133, payload: Array("A".utf8))])
    }

    func testByteAtATimeMatchesWholeChunk() {
        let input = Array("pre\u{1b}]7;file://h/a%20b\u{1b}\\mid\u{1b}]133;D;1\u{07}post".utf8)
        var whole = OSCScanner()
        let expected = whole.scan(ArraySlice(input))

        var piecewise = OSCScanner()
        var got: [OSCSequence] = []
        for b in input { got += piecewise.scan(ArraySlice([b])) }
        XCTAssertEqual(got, expected)
        XCTAssertEqual(expected.count, 2)
    }
}
