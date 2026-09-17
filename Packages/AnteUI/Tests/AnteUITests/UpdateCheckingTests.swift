// Packages/AnteUI/Tests/AnteUITests/UpdateCheckingTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class FakeUpdater: UpdateChecking {
    var automaticallyChecks = true
    var canCheck = true
    var checks = 0
    func checkNow() { checks += 1 }
}

@MainActor
final class UpdateCheckingTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-upd-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeRuntime() -> WorkspaceRuntime {
        let paths = AppPaths(root: root.appendingPathComponent("state"), configRoot: root.appendingPathComponent("config"))
        return WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: ["PATH=/usr/bin:/bin"], kind: .other)
        })
    }

    func testRuntimeHasNoUpdaterUntilTheAppInstallsOne() {
        let runtime = makeRuntime()
        XCTAssertNil(runtime.updater)
        let fake = FakeUpdater()
        runtime.updater = fake
        runtime.updater?.checkNow()
        XCTAssertEqual(fake.checks, 1)
    }
}

extension UpdateCheckingTests {
    func testSettingsForwardsTheAutomaticSwitchToTheUpdater() {
        let runtime = makeRuntime()
        let fake = FakeUpdater()
        runtime.updater = fake
        let model = SettingsModel(runtime: runtime)
        XCTAssertTrue(model.automaticUpdates)
        model.automaticUpdates = false
        XCTAssertFalse(fake.automaticallyChecks)
        runtime.updater = nil
        XCTAssertFalse(model.automaticUpdates, "no updater: the switch reads as off and writes go nowhere")
    }
}
