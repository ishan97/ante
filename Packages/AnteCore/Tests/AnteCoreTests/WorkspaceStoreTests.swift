// Packages/AnteCore/Tests/AnteCoreTests/WorkspaceStoreTests.swift
import XCTest
@testable import AnteCore

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUp() {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ante-ws-\(UUID().uuidString)")
        paths = AppPaths(root: tempRoot.appendingPathComponent("state"), configRoot: tempRoot.appendingPathComponent("config"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(stateStore: StateStore(paths: paths), saveDelay: .milliseconds(20))
    }

    func testAddProjectNamesItAfterTheFolderAndDedupes() {
        let store = makeStore()
        let p1 = store.addProject(rootDirectory: URL(fileURLWithPath: "/Users/t/code/ante"))
        XCTAssertEqual(p1.name, "ante")
        let p2 = store.addProject(rootDirectory: URL(fileURLWithPath: "/Users/t/code/ante/"))
        XCTAssertEqual(p1.id, p2.id, "same folder must not create a second project")
        XCTAssertEqual(store.state.projects.count, 1)
    }

    func testAddSessionOrdersAndNamesSequentially() {
        let store = makeStore()
        let p = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p"))
        let a = store.addSession(in: p.id)
        let b = store.addSession(in: p.id)
        XCTAssertEqual(a.name, "Terminal")
        XCTAssertEqual(b.name, "Terminal 2")
        XCTAssertEqual(a.workingDirectory, p.rootDirectory)
        XCTAssertLessThan(a.order, b.order)
        XCTAssertEqual(store.state.focusedSessionID, b.id, "a new session takes focus")
    }

    func testRemoveProjectRemovesItsSessionsAndMovesFocus() {
        let store = makeStore()
        let p1 = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p1"))
        let p2 = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p2"))
        let s1 = store.addSession(in: p1.id)
        _ = store.addSession(in: p2.id)
        store.focus(s1.id)
        store.removeProject(p1.id)
        XCTAssertEqual(store.state.projects.map(\.id), [p2.id])
        XCTAssertFalse(store.state.sessions.contains { $0.projectID == p1.id })
        XCTAssertNotEqual(store.state.focusedSessionID, s1.id)
        XCTAssertNotNil(store.state.focusedSessionID)
    }

    func testMoveSessionReordersWithinProject() {
        let store = makeStore()
        let p = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p"))
        let a = store.addSession(in: p.id)
        let b = store.addSession(in: p.id)
        let c = store.addSession(in: p.id)
        store.moveSession(c.id, toOrder: 0)
        XCTAssertEqual(store.visibleSessions(in: p.id).map(\.id), [c.id, a.id, b.id])
    }

    func testScratchSessionIsHiddenFromVisibleSessions() {
        let store = makeStore()
        let p = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p"))
        let scratch = store.addSession(in: p.id, name: "Scratch", isScratch: true)
        _ = store.addSession(in: p.id)
        XCTAssertEqual(store.scratchSession?.id, scratch.id)
        XCTAssertFalse(store.visibleSessions(in: p.id).contains { $0.isScratch })
        XCTAssertNotEqual(store.state.focusedSessionID, scratch.id, "scratch never takes sidebar focus")
    }

    func testMutationsAreDebouncedThenPersisted() async throws {
        let store = makeStore()
        let p = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p"))
        _ = store.addSession(in: p.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path), "not saved synchronously")
        await store.flushPendingSave()
        let reloaded = StateStore(paths: paths).load().state
        XCTAssertEqual(reloaded, store.state)
    }

    func testSaveNowWritesImmediately() throws {
        let store = makeStore()
        _ = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp/p"))
        store.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testLoadsExistingStateAndSurfacesNotice() throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: paths.stateFile)
        let store = makeStore()
        XCTAssertEqual(store.state, .empty)
        guard case .startedFresh? = store.loadNotice else { return XCTFail("expected notice") }
    }

    func testAutoNameNeverReplacesAUserRename() {
        let store = makeStore()
        let project = store.addProject(rootDirectory: URL(fileURLWithPath: "/tmp"))
        let session = store.addSession(in: project.id)
        store.setAutoName("Fix the login bug", for: session.id)
        XCTAssertEqual(store.state.sessions.first { $0.id == session.id }?.name, "Fix the login bug")
        store.renameSession(session.id, to: "Mine")
        store.setAutoName("Something else", for: session.id)
        XCTAssertEqual(store.state.sessions.first { $0.id == session.id }?.name, "Mine")
        XCTAssertTrue(store.state.sessions.first { $0.id == session.id }!.isUserNamed)
    }

    func testIsScratchDecodesAsFalseWhenAbsent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","projectID":"\(UUID().uuidString)","name":"x",
         "workingDirectory":"file:///tmp/","order":0,"createdAt":1.0}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertFalse(session.isScratch)
    }
}
