// Packages/AnteCore/Tests/AnteCoreTests/ConfigWatcherTests.swift
import XCTest
@testable import AnteCore

@MainActor
final class ConfigWatcherTests: XCTestCase {
    func testEditingTheConfigFileDeliversTheNewConfig() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-cw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        try FileManager.default.createDirectory(at: paths.configRoot, withIntermediateDirectories: true)
        try Data("[font]\nsize = 13\n".utf8).write(to: paths.configFile)

        let received = expectation(description: "config reloaded")
        var latest: AnteConfig?
        let watcher = ConfigWatcher(paths: paths, debounce: .milliseconds(50)) { result in
            latest = result.config
            if result.config.font.size == 17 { received.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }

        // Editors save via write-to-temp-then-rename; emulate that.
        let temp = paths.configRoot.appendingPathComponent("config.toml.tmp")
        try Data("[font]\nsize = 17\n".utf8).write(to: temp)
        _ = try FileManager.default.replaceItemAt(paths.configFile, withItemAt: temp)

        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(latest?.font.size, 17)
    }

    func testInPlaceWritesAreNoticedToo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-cw2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        try FileManager.default.createDirectory(at: paths.configRoot, withIntermediateDirectories: true)
        try Data("[font]\nsize = 13\n".utf8).write(to: paths.configFile)

        let received = expectation(description: "config reloaded after an in-place write")
        let watcher = ConfigWatcher(paths: paths, debounce: .milliseconds(50)) { result in
            if result.config.font.size == 19 { received.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }

        // VS Code and friends truncate and rewrite the same file: no directory entry changes.
        let handle = try FileHandle(forWritingTo: paths.configFile)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("[font]\nsize = 19\n".utf8))
        try handle.close()

        await fulfillment(of: [received], timeout: 5)
    }
}
