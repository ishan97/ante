// Packages/AnteTerm/Tests/AnteTermTests/LinkDetectorTests.swift
import XCTest
@testable import AnteTerm

final class LinkDetectorTests: XCTestCase {
    func testFindsHttpUrlsWithColumns() {
        let line = "see https://example.com/a?b=1 and http://x.org."
        let matches = LinkDetector.detect(in: line)
        XCTAssertEqual(matches.count, 2)
        guard case let .url(first) = matches[0].kind else { return XCTFail() }
        XCTAssertEqual(first.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(matches[0].range, 4..<29)
        guard case let .url(second) = matches[1].kind else { return XCTFail() }
        XCTAssertEqual(second.absoluteString, "http://x.org", "trailing period is not part of the URL")
    }

    func testRejectsDisallowedSchemes() {
        XCTAssertTrue(LinkDetector.detect(in: "javascript:alert(1) ftp://host/x ssh://h").isEmpty)
        XCTAssertEqual(LinkDetector.detect(in: "mailto:a@b.co").count, 1)
        XCTAssertEqual(LinkDetector.detect(in: "file:///tmp/x").count, 1)
    }

    func testFindsExistingPathsOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ante-ld-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("main.swift")
        try Data("x".utf8).write(to: file)
        let line = "error in \(file.path):12:3 and /definitely/not/here.txt"
        let matches = LinkDetector.detect(in: line)
        XCTAssertEqual(matches.count, 1)
        guard case let .path(path, lineNumber) = matches[0].kind else { return XCTFail("\(matches)") }
        XCTAssertEqual(path, file.path)
        XCTAssertEqual(lineNumber, 12)
    }

    func testMatchAtColumn() {
        let line = "go to https://example.com now"
        XCTAssertNotNil(LinkDetector.match(in: line, atColumn: 10))
        XCTAssertNil(LinkDetector.match(in: line, atColumn: 2))
        XCTAssertNil(LinkDetector.match(in: line, atColumn: 40))
    }
}

extension LinkDetectorTests {
    func testRelativePathsResolveAgainstThePaneDirectoryOnly() {
        let base = URL(fileURLWithPath: "/work/proj")
        let seen = { (p: String) -> Bool in p == "/work/proj/src/main.swift" || p == "/work/main.swift" }
        // Without a base, a relative path is never linked, whatever the process cwd holds.
        XCTAssertTrue(LinkDetector.detect(in: "see ./src/main.swift:3", fileExists: seen).isEmpty)
        let m = LinkDetector.detect(in: "see ./src/main.swift:3 and ../main.swift", relativeTo: base, fileExists: seen)
        XCTAssertEqual(m.count, 2)
        if case let .path(p, line) = m[0].kind { XCTAssertEqual(p, "/work/proj/src/main.swift"); XCTAssertEqual(line, 3) } else { XCTFail() }
        if case let .path(p, _) = m[1].kind { XCTAssertEqual(p, "/work/main.swift") } else { XCTFail() }
    }
}
