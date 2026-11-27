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
        XCTAssertEqual(ours[0]["command"] as? String, installer.command)
        XCTAssertTrue(installer.command.contains("ANTE_PANE_ID") && installer.command.hasSuffix("# ante-hook-v4"))

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

    // MARK: - v2: SessionStart and pane-tagged events

    private func settingsWith(_ json: String) throws -> URL {
        let settings = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: settings)
        return settings
    }

    func testInstallAddsSessionStartAndMarker() throws {
        let settings = try settingsWith("{}")
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: root.appendingPathComponent("hooks/claude.jsonl"))
        try installer.install()
        let hooks = try loadHooks(settings)
        XCTAssertEqual(Set(hooks.keys), ["Notification", "Stop", "UserPromptSubmit", "SessionStart"])
    }

    func testOldFormatIsNotInstalledAndUpgrades() throws {
        let events = root.appendingPathComponent("hooks/claude.jsonl")
        let v1 = #"{"matcher":"","hooks":[{"type":"command","command":"cat >> \"EVENTS\""}]}"#.replacingOccurrences(of: "EVENTS", with: events.path)
        let mine = #"{"matcher":"","hooks":[{"type":"command","command":"say done"}]}"#
        let settings = try settingsWith(#"{"hooks":{"Notification":[V1],"Stop":[MINE,V1],"UserPromptSubmit":[V1]}}"#
            .replacingOccurrences(of: "V1", with: v1).replacingOccurrences(of: "MINE", with: mine))
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: events)
        XCTAssertFalse(installer.isInstalled(), "a v1 install needs the upgrade")
        XCTAssertTrue(installer.hasAnyInstall())
        try installer.upgradeIfInstalled()
        XCTAssertTrue(installer.isInstalled())
        let hooks = try loadHooks(settings)
        let stop = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2, "the person's own Stop hook is kept, ours replaced")
        XCTAssertEqual((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String, "say done")
        XCTAssertNotNil(hooks["SessionStart"])
    }

    /// The person removed Ante's Notification entry by hand: an upgrade must not bring it back.
    func testUpgradeKeepsEventsThePersonRemoved() throws {
        let events = root.appendingPathComponent("hooks/claude.jsonl")
        let old = #"{"matcher":"","hooks":[{"type":"command","command":"x >> \"EVENTS\" # ante-hook-v2"}]}"#.replacingOccurrences(of: "EVENTS", with: events.path)
        let settings = try settingsWith(#"{"hooks":{"Stop":[OLD],"UserPromptSubmit":[OLD],"SessionStart":[OLD]}}"#.replacingOccurrences(of: "OLD", with: old))
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: events)
        try installer.upgradeIfInstalled()
        let hooks = try loadHooks(settings)
        XCTAssertNil(hooks["Notification"], "not re-added")
        for event in ["Stop", "UserPromptSubmit", "SessionStart"] {
            let command = (((hooks[event] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["command"] as! String)
            XCTAssertEqual(command, installer.command, event)
        }
        let again = try String(contentsOf: settings, encoding: .utf8)
        try installer.upgradeIfInstalled()
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), again, "current now: nothing more to write")
    }

    func testUpgradeNoOpWhenAbsent() throws {
        let json = #"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"say done"}]}]}}"#
        let settings = try settingsWith(json)
        let installer = ClaudeHookInstaller(settingsFile: settings, eventFile: root.appendingPathComponent("hooks/claude.jsonl"))
        try installer.upgradeIfInstalled()
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), json)
        let backups = try FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path).filter { $0.contains("ante-backup") }
        XCTAssertEqual(backups, [], "nothing written, nothing backed up")
    }

    func testParsesPaneTaggedLine() {
        let line = "p1\t" + #"{"hook_event_name":"SessionStart","session_id":"s-new","cwd":"/p","source":"clear"}"# + "\n"
        let events = HookEvent.parse(Data(line.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.paneID, "p1")
        XCTAssertEqual(events.first?.sessionID, "s-new")
        XCTAssertEqual(events.first?.meaning, .other)
    }

    func testParsesPlainAndUntaggedLines() {
        let data = Data((#"{"hook_event_name":"Stop","session_id":"a","cwd":"/p"}"# + "\n" + "\t" + #"{"hook_event_name":"Stop","session_id":"b","cwd":"/p"}"# + "\n").utf8)
        let events = HookEvent.parse(data)
        XCTAssertEqual(events.map(\.sessionID), ["a", "b"])
        XCTAssertEqual(events.map(\.paneID), [nil, nil])
    }

    func testHookCommandWritesTaggedLineInAShell() throws {
        let events = root.appendingPathComponent("hooks dir/claude.jsonl")
        try FileManager.default.createDirectory(at: events.deletingLastPathComponent(), withIntermediateDirectories: true)
        let installer = ClaudeHookInstaller(settingsFile: root.appendingPathComponent("s.json"), eventFile: events)
        for pane in ["p1", ""] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", installer.command]
            process.environment = pane.isEmpty ? [:] : ["ANTE_PANE_ID": pane]
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"hook_event_name":"Stop","session_id":"abc","cwd":"/p"}"#.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
        }
        let parsed = HookEvent.parse(try Data(contentsOf: events))
        XCTAssertEqual(parsed.map(\.paneID), ["p1", nil])
        XCTAssertEqual(parsed.map(\.sessionID), ["abc", "abc"])
    }

    func testMisalignedLinesAreDroppedNotMisattributed() {
        let json = #"{"hook_event_name":"SessionStart","session_id":"other","cwd":"/p"}"#
        for line in ["A\t\t\t" + json, "A\tB\t" + json, "A\t " + json, "A B\t" + json, "A\tx" + json, "A\t12\tB\t" + json,
                     "A\t-1\t" + json] {
            XCTAssertEqual(HookEvent.parse(Data((line + "\n").utf8)).count, 0, line)
        }
    }

    /// Hooks from several panes firing at once must each land as one whole line, with its own pane.
    func testConcurrentHooksWriteWholeLines() throws {
        let events = root.appendingPathComponent("hooks/claude.jsonl")
        try FileManager.default.createDirectory(at: events.deletingLastPathComponent(), withIntermediateDirectories: true)
        let installer = ClaudeHookInstaller(settingsFile: root.appendingPathComponent("s.json"), eventFile: events)
        let script = root.appendingPathComponent("hook.sh")
        try installer.command.write(to: script, atomically: true, encoding: .utf8)
        let runs = 40
        let driver = Process()
        driver.executableURL = URL(fileURLWithPath: "/bin/sh")
        driver.arguments = ["-c", """
            i=0
            while [ $i -lt \(runs) ]; do
              for p in A B; do
                printf '{"hook_event_name":"Stop","session_id":"s%s","cwd":"/p"}' $p | ANTE_PANE_ID=$p sh "$0" &
              done
              i=$((i+1))
            done
            wait
            """, script.path]
        try driver.run()
        driver.waitUntilExit()
        let parsed = HookEvent.parse(try Data(contentsOf: events))
        XCTAssertEqual(parsed.count, runs * 2, "every line intact")
        XCTAssertTrue(parsed.allSatisfy { ($0.processID ?? 0) > 1 }, "each names the process that ran it")
        XCTAssertTrue(parsed.allSatisfy { $0.sessionID == "s" + ($0.paneID ?? "?") }, "each event credited to its own pane")
    }
}
