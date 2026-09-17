import XCTest
@testable import AnteCore

final class ModelTests: XCTestCase {
    func testIdentifiersAreDistinctTypes() {
        let s = SessionID()
        let p = ProjectID()
        XCTAssertNotEqual(s.rawValue, p.rawValue)
        XCTAssertEqual(SessionID(rawValue: s.rawValue), s)
    }

    func testSessionRoundTripsThroughJSON() throws {
        let project = Project(name: "ante", rootDirectory: URL(fileURLWithPath: "/tmp/ante"))
        let session = Session(
            projectID: project.id,
            name: "build",
            workingDirectory: URL(fileURLWithPath: "/tmp/ante/Packages"),
            lastCommand: "swift build"
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
    }

    func testAppStateEmptyHasCurrentSchemaVersion() {
        let state = AppState.empty
        XCTAssertEqual(state.schemaVersion, AppState.currentSchemaVersion)
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertNil(state.focusedSessionID)
    }

    func testSessionsForProjectAreOrdered() {
        let p = Project(name: "a", rootDirectory: URL(fileURLWithPath: "/a"))
        let s1 = Session(projectID: p.id, name: "one", workingDirectory: p.rootDirectory, order: 2)
        let s2 = Session(projectID: p.id, name: "two", workingDirectory: p.rootDirectory, order: 1)
        var state = AppState.empty
        state.projects = [p]
        state.sessions = [s1, s2]
        XCTAssertEqual(state.sessions(in: p.id).map(\.name), ["two", "one"])
    }
}
