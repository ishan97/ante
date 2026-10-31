import XCTest
@testable import AnteUI
import AnteCore

final class SidebarDropTests: XCTestCase {
    private let p = ProjectID(), q = ProjectID()
    private let a = SessionID(), b = SessionID(), x = SessionID()

    /// p's header at 0…20 with rows a (20…48) and b (50…78); q's header at 90…110 with row x (110…138).
    private var sections: [SidebarDropTarget.Section] {
        [SidebarDropTarget.Section(project: p, header: CGRect(x: 0, y: 0, width: 232, height: 20),
                                   rows: [(a, CGRect(x: 8, y: 20, width: 216, height: 28)), (b, CGRect(x: 8, y: 50, width: 216, height: 28))]),
         SidebarDropTarget.Section(project: q, header: CGRect(x: 0, y: 90, width: 232, height: 20),
                                   rows: [(x, CGRect(x: 8, y: 110, width: 216, height: 28))])]
    }

    private func target(_ y: CGFloat, x px: CGFloat = 100, dragging: SessionID) -> SidebarDropTarget? {
        SidebarDropTarget.at(CGPoint(x: px, y: y), width: 232, sections: sections, dragging: dragging)
    }

    func testDropWithinAndAcrossProjects() {
        // b dragged above a: first in p.
        XCTAssertEqual(target(25, dragging: b), SidebarDropTarget(project: p, index: 0, lineY: 19))
        // a dragged below b: last in p (its own row does not count).
        XCTAssertEqual(target(70, dragging: a), SidebarDropTarget(project: p, index: 1, lineY: 79))
        // a dragged onto q's header: first in q.
        XCTAssertEqual(target(95, dragging: a), SidebarDropTarget(project: q, index: 0, lineY: 109))
        // a dragged below x: after x in q.
        XCTAssertEqual(target(130, dragging: a), SidebarDropTarget(project: q, index: 1, lineY: 139))
        // Just under the last row: the end of the last project.
        XCTAssertEqual(target(150, dragging: a), SidebarDropTarget(project: q, index: 1, lineY: 139))
        // Just above the first header: the top of the first project.
        XCTAssertEqual(target(-5, dragging: x), SidebarDropTarget(project: p, index: 0, lineY: 19))
    }

    func testOutsideTheListCancels() {
        XCTAssertNil(target(30, x: -5, dragging: a))
        XCTAssertNil(target(30, x: 400, dragging: a))
        // Pulled well above or below the list: cancelled, not moved to the first or last project.
        XCTAssertNil(target(-40, dragging: a))
        XCTAssertNil(target(900, dragging: a))
        XCTAssertNil(SidebarDropTarget.at(.zero, width: 232, sections: [], dragging: a))
    }

    func testEmptyProjectTakesTheDropUnderItsHeader() {
        let empty = [SidebarDropTarget.Section(project: q, header: CGRect(x: 0, y: 0, width: 232, height: 20), rows: [])]
        XCTAssertEqual(SidebarDropTarget.at(CGPoint(x: 50, y: 40), width: 232, sections: empty, dragging: a),
                       SidebarDropTarget(project: q, index: 0, lineY: 21))
    }
}
