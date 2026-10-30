import XCTest
@testable import AnteUI
import AnteCore

@MainActor
final class TipsAndTokensTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "ante-tips-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let catalogue = [
        Tip(id: "a", symbol: "star", [.text("A")]),
        Tip(id: "b", symbol: "star", [.text("B "), .key("⌘B")]),
    ]

    func testTipsRotateAreSpacedAndStopAfterFiveShows() {
        let model = TipsModel(defaults: defaults)
        var now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(model.presentIfDue(catalogue, now: now))
        XCTAssertEqual(model.current?.id, "a")
        XCTAssertFalse(model.presentIfDue(catalogue, now: now), "one at a time")
        model.close()
        XCTAssertFalse(model.presentIfDue(catalogue, now: now.addingTimeInterval(60)), "too soon after the last one")
        var seen: [String] = ["a"]
        for _ in 0..<12 {
            now += TipsModel.spacing
            if model.presentIfDue(catalogue, now: now) { seen.append(model.current!.id); model.close() }
        }
        XCTAssertEqual(seen, ["a", "b", "a", "b", "a", "b", "a", "b", "a", "b"], "least seen first, five each, then no more")
        XCTAssertNil(model.next(from: catalogue))
    }

    func testDontShowAgainAndTurningOffPersist() {
        let model = TipsModel(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        model.presentIfDue(catalogue, now: now)
        model.hideCurrentForever()
        XCTAssertNil(model.current)
        let reloaded = TipsModel(defaults: defaults)
        XCTAssertEqual(reloaded.hidden, ["a"])
        XCTAssertEqual(reloaded.shows["a"], 1)
        XCTAssertEqual(reloaded.next(from: catalogue)?.id, "b")
        reloaded.isEnabled = false
        XCTAssertFalse(reloaded.presentIfDue(catalogue, now: now.addingTimeInterval(TipsModel.spacing * 2)))
        XCTAssertFalse(TipsModel(defaults: defaults).isEnabled)
        reloaded.reset()
        let fresh = TipsModel(defaults: defaults)
        XCTAssertTrue(fresh.isEnabled)
        XCTAssertTrue(fresh.hidden.isEmpty)
        XCTAssertTrue(fresh.presentIfDue(catalogue, now: now))
        XCTAssertEqual(fresh.current?.id, "a")
    }

    func testTurningOffHidesTheTipOnScreen() {
        let model = TipsModel(defaults: defaults)
        model.presentIfDue(catalogue)
        model.isEnabled = false
        XCTAssertNil(model.current)
    }

    func testCatalogueTeachesTheUsersOwnKeys() {
        var keys = AnteConfig.Keys()
        keys.toggleFullscreen = KeyBinding(key: "f", modifiers: [.cmd, .ctrl])
        let tips = TipCatalog.tips(keys: keys, hotkey: "⌥`")
        XCTAssertEqual(tips.first?.id, "hotkey")
        XCTAssertTrue(tips.first!.plainText.contains("⌥`"))
        XCTAssertTrue(tips.first { $0.id == "fill-screen" }!.plainText.hasPrefix(keys.toggleFullscreen.display))
        XCTAssertEqual(Set(tips.map(\.id)).count, tips.count, "ids are unique")
        XCTAssertNil(TipCatalog.tips(keys: keys, hotkey: nil).first { $0.id == "hotkey" }, "no hotkey, no hotkey tip")
    }

    func testCompactTokenCounts() {
        XCTAssertEqual(TokenUsageModel.compact(0), "0")
        XCTAssertEqual(TokenUsageModel.compact(999), "999")
        XCTAssertEqual(TokenUsageModel.compact(1_000), "1K")
        XCTAssertEqual(TokenUsageModel.compact(1_249), "1.24K")
        XCTAssertEqual(TokenUsageModel.compact(12_480), "12.4K")
        XCTAssertEqual(TokenUsageModel.compact(999_999), "999K")
        XCTAssertEqual(TokenUsageModel.compact(9_904_092), "9.9M")
        XCTAssertEqual(TokenUsageModel.compact(1_619_637_056), "1.61B")
        XCTAssertEqual(TokenUsageModel.compact(6_342_988_158_000), "6.34T")
        XCTAssertEqual(TokenUsageModel.compact(1_130), "1.13K", "no binary-double floor")
        XCTAssertEqual(TokenUsageModel.compact(1_150), "1.15K")
        XCTAssertEqual(TokenUsageModel.compact(2_010), "2.01K")
        XCTAssertEqual(TokenUsageModel.compact(1_005_000), "1M", "1.005 truncates to 1.00")
        XCTAssertEqual(TokenUsageModel.compact(10_050_000), "10M")
        XCTAssertEqual(TokenUsageModel.compact(100_999_999), "100M")
    }

    func testPercentLabels() {
        XCTAssertEqual(TokenUsageView.percent(0, of: 0), "")
        XCTAssertEqual(TokenUsageView.percent(1, of: 1_000), "<1%")
        XCTAssertEqual(TokenUsageView.percent(995, of: 1_000), "100%")
        XCTAssertEqual(TokenUsageView.percent(1, of: 3), "33%")
    }

    func testTimerTipUsesTheUsersLengths() {
        let tip = TipCatalog.tips(keys: AnteConfig.Keys(), hotkey: nil, focusMinutes: 50, breakMinutes: 10).first { $0.id == "focus-timer" }
        XCTAssertTrue(tip!.plainText.contains("50 minutes on, 10 off"))
    }
}
