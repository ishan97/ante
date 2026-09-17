import XCTest
@testable import AnteCore

final class StateStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var paths: AppPaths!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ante-tests-\(UUID().uuidString)")
        paths = AppPaths(root: tempRoot.appendingPathComponent("state"),
                         configRoot: tempRoot.appendingPathComponent("config"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testMissingFileLoadsEmptyStateWithoutNotice() {
        let store = StateStore(paths: paths)
        let result = store.load()
        XCTAssertEqual(result.state, .empty)
        XCTAssertNil(result.notice)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = StateStore(paths: paths)
        let project = Project(name: "p", rootDirectory: URL(fileURLWithPath: "/p"))
        // Whole milliseconds: the file format keeps fractional seconds to the millisecond.
        let session = Session(projectID: project.id, name: "s", workingDirectory: project.rootDirectory,
                              createdAt: Date(timeIntervalSince1970: 1_757_400_000.250))
        var state = AppState.empty
        state.projects = [project]
        state.sessions = [session]
        state.focusedSessionID = session.id
        try store.save(state)

        let result = store.load()
        XCTAssertEqual(result.state, state)
        XCTAssertNil(result.notice)
    }

    func testSavedFileIsOwnerReadWriteOnly() throws {
        let store = StateStore(paths: paths)
        try store.save(.empty)
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.stateFile.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testCorruptFileIsBackedUpAndStartsFresh() throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: paths.stateFile)
        let store = StateStore(paths: paths)
        let result = store.load()
        XCTAssertEqual(result.state, .empty)
        guard case let .startedFresh(reason, backupURL)? = result.notice else {
            return XCTFail("expected startedFresh, got \(String(describing: result.notice))")
        }
        XCTAssertTrue(reason.contains("unreadable"))
        let backup = try XCTUnwrap(backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{not json")
    }

    func testNewerSchemaIsBackedUpAndStartsFresh() throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let future = AppState.currentSchemaVersion + 5
        let json = """
        {"schemaVersion": \(future), "projects": [], "sessions": [], "someFutureKey": 1}
        """
        try Data(json.utf8).write(to: paths.stateFile)
        let store = StateStore(paths: paths)
        let result = store.load()
        XCTAssertEqual(result.state, .empty)
        guard case let .startedFresh(reason, backupURL)? = result.notice else {
            return XCTFail("expected startedFresh")
        }
        XCTAssertTrue(reason.contains("newer"))
        XCTAssertEqual(backupURL?.lastPathComponent, "state.json.bak-v\(future)")
    }

    func testOlderSchemaRunsMigrationsAndRewritesFile() throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        // A pretend v0 file where projects were called "folders".
        let json = """
        {"schemaVersion": 0, "folders": [], "sessions": []}
        """
        try Data(json.utf8).write(to: paths.stateFile)

        let migrations = Migrations(steps: [
            0: { dict in
                dict["projects"] = dict.removeValue(forKey: "folders") ?? []
                dict["schemaVersion"] = 1
            },
        ])
        let store = StateStore(paths: paths, migrations: migrations)
        let result = store.load()
        XCTAssertEqual(result.state.schemaVersion, 1)
        XCTAssertEqual(result.notice, .migrated(from: 0, to: 1))

        let rewritten = try Data(contentsOf: paths.stateFile)
        let obj = try JSONSerialization.jsonObject(with: rewritten) as? [String: Any]
        XCTAssertEqual(obj?["schemaVersion"] as? Int, 1)
        XCTAssertNil(obj?["folders"])
    }

    func testMissingMigrationStepStartsFresh() throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 0, "projects": [], "sessions": []}"#.utf8).write(to: paths.stateFile)
        let store = StateStore(paths: paths, migrations: Migrations(steps: [:]))
        let result = store.load()
        XCTAssertEqual(result.state, .empty)
        guard case let .startedFresh(reason, _)? = result.notice else { return XCTFail() }
        XCTAssertTrue(reason.contains("migration"))
    }
}
