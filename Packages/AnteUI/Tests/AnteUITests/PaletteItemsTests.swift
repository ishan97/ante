// Packages/AnteUI/Tests/AnteUITests/PaletteItemsTests.swift
import XCTest
import AnteCore
import AnteTerm
@testable import AnteUI

@MainActor
final class PaletteItemsTests: XCTestCase {
    func testPaletteListsSessionsProjectsActionsThemesAndDirectories() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-pal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, configRoot: root.appendingPathComponent("config"))
        let runtime = WorkspaceRuntime(paths: paths, config: .default, launchFactory: { _ in
            ShellLaunch(executable: "/bin/sh", arguments: ["-c", "sleep 30"], environment: [], kind: .other)
        })
        let items = PaletteItems.build(runtime: runtime, toggleWindow: {})
        XCTAssertTrue(items.contains { $0.kind == .session && $0.title == "Terminal" })
        XCTAssertTrue(items.contains { $0.kind == .project && $0.title == "New Session in Home" })
        XCTAssertTrue(items.contains { $0.kind == .action && $0.title == "Split Right" })
        XCTAssertTrue(items.contains { $0.kind == .theme && $0.title == "Theme: gruvbox-dark" })
        XCTAssertTrue(items.contains { $0.kind == .directory })
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "ids are unique")
        XCTAssertEqual(FuzzyMatcher.rank(items, query: "split r", text: { $0.searchText }).first?.title, "Split Right")
        runtime.prepareForQuit()
    }
}
