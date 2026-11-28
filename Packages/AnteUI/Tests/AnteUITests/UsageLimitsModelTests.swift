import XCTest
import AnteCore
@testable import AnteUI

/// Answers in place of the providers, one queued answer per check.
final class FakeUsageLimits: UsageLimitsFetching, @unchecked Sendable {
    var answers: [UsageLimits] = []
    var antigravity: [UsageLimits?] = []
    private(set) var asked = 0

    func limits(for account: AgentAccount, paths: AccountPaths) async -> UsageLimits {
        asked += 1
        return answers.isEmpty ? .unavailable : answers.removeFirst()
    }

    func antigravityLimits() async -> UsageLimits? {
        antigravity.isEmpty ? nil : antigravity.removeFirst()
    }
}

@MainActor
final class UsageLimitsModelTests: XCTestCase {
    private var base: URL!
    private var paths: AccountPaths!
    private var cli: FakeAgentCLI!
    private var limits: FakeUsageLimits!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("ulm-\(UUID().uuidString)")
        let home = base.appendingPathComponent("home")
        paths = AccountPaths(root: home.appendingPathComponent(".ante/accounts"), home: home)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        cli = FakeAgentCLI()
        cli.set(.claude, AgentStatus(loggedIn: true, email: "a@x.com", org: "A", plan: "Max", isSubscription: true))
        limits = FakeUsageLimits()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func model() async -> (AccountsModel, AgentAccount) {
        let m = AccountsModel(paths: paths, cli: cli, limits: limits)
        await m.importExistingLogins()
        return (m, m.accounts(for: .claude)[0])
    }

    private let windows = UsageLimits.windows([UsageWindow(label: "5h", percentLeft: 56, resetsAt: nil)])

    func testRefreshShowsEachAccountsLine() async {
        let (m, account) = await model()
        XCTAssertNil(m.limitsLine(for: account), "nothing before the first check")
        limits.answers = [windows]
        limits.antigravity = [.windows([UsageWindow(label: "Gemini", percentLeft: 98, resetsAt: nil)])]
        await m.refreshLimits()
        XCTAssertEqual(m.limitsLine(for: account), "5h 56%")
        XCTAssertEqual(m.antigravityLimitsLine, "Gemini 98%")
    }

    func testFailedCheckKeepsTheLastNumbers() async {
        let (m, account) = await model()
        limits.answers = [windows, .unavailable]
        await m.refreshLimits()
        await m.refreshLimits()
        XCTAssertEqual(m.limits(for: account), windows, "a rate-limited check must not blank the line")
    }

    func testExpiredTokenAsksToRenew() async {
        let (m, account) = await model()
        limits.answers = [windows, .tokenExpired]
        limits.antigravity = [.windows([UsageWindow(label: "Gemini", percentLeft: 98, resetsAt: nil)]), .tokenExpired]
        await m.refreshLimits()
        await m.refreshLimits()
        XCTAssertEqual(m.limitsLine(for: account), UsageLimitsFormat.expiredLine)
        XCTAssertEqual(m.antigravityLimitsLine, "Token expired — start agy to renew it")
    }
}

final class RenewalLockTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)/account")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

    private var primary: String { folder.appendingPathComponent(".oauth_refresh.lock").path }
    private var legacy: String { folder.resolvingSymlinksInPath().path + ".lock" }

    func testTakesBothLocksAndReleasesThem() throws {
        let lock = try XCTUnwrap(RenewalLock.take(configFolder: folder))
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy))
        XCTAssertNil(RenewalLock.take(configFolder: folder), "held: a second taker gives up")
        XCTAssertTrue(lock.isStillHeld)
        lock.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy))
    }

    func testGivesUpWhenClaudeCodeHoldsEitherLock() throws {
        try FileManager.default.createDirectory(atPath: legacy, withIntermediateDirectories: false)
        XCTAssertNil(RenewalLock.take(configFolder: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary), "the half it took is let go")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy), "someone else's lock is never removed")
    }

    func testLeavesALockSomeoneElseTookOver() throws {
        let lock = try XCTUnwrap(RenewalLock.take(configFolder: folder))
        try FileManager.default.removeItem(atPath: primary)
        try FileManager.default.createDirectory(atPath: primary, withIntermediateDirectories: false)
        XCTAssertFalse(lock.isStillHeld, "taken over: Ante must not go on to post")
        lock.release()
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary), "replaced meanwhile: it is theirs now")
    }
}
