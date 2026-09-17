// Packages/AnteCore/Tests/AnteCoreTests/HookTests.swift
import XCTest
@testable import AnteCore

final class HookTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func loadHooks(_ settings: URL) throws -> [String: Any] {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        return root["hooks"] as? [String: Any] ?? [:]
    }

    func testInstallAddsOurGroupsKeepsOthersBacksUpAndUninstallRestores() throws {
        let settings = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}],"Stop":[{"matcher":"","hooks":[{"type":"command","command":"say done"}]}]}}"#
        try Data(original.utf8).write(to: settings)
        let events = root.appendingPathComponent("hooks/claude.jsonl")
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: events)
        XCTAssertFalse(installer.isInstalled())

        try installer.install()
        XCTAssertTrue(installer.isInstalled())
        XCTAssertTrue(FileManager.default.fileExists(atPath: events.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path).filter { $0.contains("ante-backup") }
        XCTAssertEqual(backups.count, 1)

        let installedRoot = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual(installedRoot["model"] as? String, "opus")
        var hooks = try loadHooks(settings)
        XCTAssertEqual((hooks["PreToolUse"] as! [[String: Any]]).count, 1, "unrelated hook untouched")
        XCTAssertEqual((hooks["Stop"] as! [[String: Any]]).count, 2, "user's Stop hook kept, ours appended")
        XCTAssertEqual((hooks["Notification"] as! [[String: Any]]).count, 1)
        let ours = (hooks["Notification"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]]
        XCTAssertEqual(ours[0]["command"] as? String, "cat >> \"\(events.path)\"")

        try installer.install()   // idempotent
        hooks = try loadHooks(settings)
        XCTAssertEqual((hooks["Stop"] as! [[String: Any]]).count, 2)

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled())
        hooks = try loadHooks(settings)
        XCTAssertEqual(Set(hooks.keys), ["PreToolUse", "Stop"])
        XCTAssertEqual(((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["command"] as? String, "say done")
    }

    func testInstallIntoMissingSettingsCreatesIt() throws {
        let settings = root.appendingPathComponent("nope/settings.json")
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: root.appendingPathComponent("hooks/claude.jsonl"))
        try installer.install()
        XCTAssertTrue(installer.isInstalled())
    }

    func testHookEventMeanings() {
        let waiting = HookEvent.fromClaude(["hook_event_name": "Notification", "notification_type": "permission_prompt",
                                            "message": "Claude needs your permission", "cwd": "/p", "session_id": "abc"])
        XCTAssertEqual(waiting?.meaning, .waiting("Claude needs your permission"))
        XCTAssertEqual(waiting?.cwd, "/p")
        XCTAssertEqual(HookEvent.fromClaude(["hook_event_name": "Stop"])?.meaning, .waiting("finished its turn"))
        if case let .waiting(text)? = HookEvent.fromClaude(["hook_event_name": "Notification", "message": "needs\u{1b}[31m you\n" + String(repeating: "!", count: 500)])?.meaning {
            XCTAssertTrue(text.hasPrefix("needs[31m you!!!"), "control characters dropped: \(text.prefix(20))")
            XCTAssertEqual(text.count, 200, "length capped")
        } else { XCTFail("expected a waiting meaning") }
        XCTAssertEqual(HookEvent.fromClaude(["hook_event_name": "UserPromptSubmit"])?.meaning, .working)
        XCTAssertEqual(HookEvent.fromClaude(["hook_event_name": "SessionStart"])?.meaning, .other)
        XCTAssertNil(HookEvent.fromClaude(["cwd": "/p"]))
    }

    @MainActor
    func testWatcherDrainsOnlyNewLinesAndSkipsGarbage() async throws {
        let file = root.appendingPathComponent("hooks/claude.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"hook_event_name\":\"Stop\"}\n".utf8).write(to: file)   // pre-existing: must be skipped
        var got: [HookEvent] = []
        let delivered = expectation(description: "events delivered by the watcher itself")
        let watcher = HookEventWatcher(file: file) { got += $0; if got.count >= 2 { delivered.fulfill() } }
        watcher.start()
        defer { watcher.stop() }
        // An in-place append, exactly what `cat >>` does: no directory entry changes.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage line\n{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\",\"cwd\":\"/x\"}\n{\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/x\"}\n".utf8))
        try handle.close()
        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertEqual(got.map(\.event), ["Notification", "UserPromptSubmit"])
        watcher.drain()
        XCTAssertEqual(got.count, 2, "no re-delivery")
    }

    @MainActor func testWatcherEmptiesAnOversizedLogOnceRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-hw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hooks/claude.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
        var count = 0
        let watcher = HookEventWatcher(file: file) { count += $0.count }
        watcher.start()
        defer { watcher.stop() }
        let handle = try FileHandle(forWritingTo: file)
        let line = "{\"hook_event_name\":\"Stop\",\"cwd\":\"/x\",\"pad\":\"" + String(repeating: "p", count: 4000) + "\"}\n"
        for _ in 0..<80 { try handle.write(contentsOf: Data(line.utf8)) }   // ~320 KB
        try handle.close()
        watcher.drain()
        XCTAssertEqual(count, 80)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64
        XCTAssertEqual(size, 0, "read past the cap: the prompt log is emptied")
    }

    func testRetentionDaysReadsAndWritesCleanupPeriod() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-ret-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: root.appendingPathComponent("events.jsonl"))
        XCTAssertEqual(installer.retentionDays(), 30, "Claude's default when the file is missing")
        try installer.setRetentionDays(365)
        XCTAssertEqual(installer.retentionDays(), 365)
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        XCTAssertEqual(obj?["cleanupPeriodDays"] as? Int, 365)
        try installer.setRetentionDays(nil)
        XCTAssertEqual(installer.retentionDays(), 30)
    }
}

extension HookTests {
    func testSettingsFileIsRewrittenOwnerOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-hook-perm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settings = root.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: root.appendingPathComponent("events.jsonl"))
        try installer.install()
        let mode = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
