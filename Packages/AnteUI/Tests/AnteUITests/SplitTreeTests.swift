// Packages/AnteUI/Tests/AnteUITests/SplitTreeTests.swift
import XCTest
@testable import AnteUI

final class SplitTreeTests: XCTestCase {
    func testSplitLeafProducesTwoPanes() {
        let a = PaneID(), b = PaneID()
        let tree = SplitTree.leaf(a).splitting(pane: a, axis: .horizontal, newPane: b)
        XCTAssertEqual(tree.paneIDs, [a, b])
        guard case let .split(axis, ratio, .leaf(l), .leaf(r)) = tree else { return XCTFail("\(tree)") }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
        XCTAssertEqual(l, a)
        XCTAssertEqual(r, b)
    }

    func testNestedSplitAndRemovalCollapses() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = SplitTree.leaf(a).splitting(pane: a, axis: .horizontal, newPane: b)
        tree = tree.splitting(pane: b, axis: .vertical, newPane: c)
        XCTAssertEqual(tree.paneIDs, [a, b, c])
        let afterRemove = tree.removing(pane: b)
        XCTAssertEqual(afterRemove?.paneIDs, [a, c])
        guard case .split(.horizontal, _, .leaf(a), .leaf(c))? = afterRemove else { return XCTFail("\(String(describing: afterRemove))") }
        XCTAssertNil(SplitTree.leaf(a).removing(pane: a), "removing the last pane removes the tree")
    }

    func testSplitBeforePutsNewPaneFirst() {
        let a = PaneID(), b = PaneID()
        let tree = SplitTree.leaf(a).splitting(pane: a, axis: .vertical, newPane: b, before: true)
        XCTAssertEqual(tree.paneIDs, [b, a])
        XCTAssertEqual(tree.neighbor(of: a, direction: .up), b)
    }

    func testNeighborNavigation() {
        let a = PaneID(), b = PaneID(), c = PaneID()
        var tree = SplitTree.leaf(a).splitting(pane: a, axis: .horizontal, newPane: b)   // [a | b]
        tree = tree.splitting(pane: b, axis: .vertical, newPane: c)                        // [a | (b / c)]
        XCTAssertEqual(tree.neighbor(of: a, direction: .right), b)
        XCTAssertEqual(tree.neighbor(of: b, direction: .left), a)
        XCTAssertEqual(tree.neighbor(of: b, direction: .down), c)
        XCTAssertEqual(tree.neighbor(of: c, direction: .up), b)
        XCTAssertEqual(tree.neighbor(of: c, direction: .left), a)
        XCTAssertNil(tree.neighbor(of: a, direction: .left))
        XCTAssertNil(tree.neighbor(of: a, direction: .up))
    }
}
