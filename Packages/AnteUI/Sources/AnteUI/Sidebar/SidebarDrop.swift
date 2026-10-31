import CoreGraphics
import AnteCore

/// Where a session dragged in the sidebar would land: which project, at which position among its
/// sessions, and the height at which to draw the insertion line. Worked out from the frames the
/// headers and rows reported, all in the sidebar list's coordinate space.
struct SidebarDropTarget: Equatable {
    let project: ProjectID
    /// Position among the project's sessions once the dragged one is taken out.
    let index: Int
    /// Where the insertion line goes.
    let lineY: CGFloat

    struct Section {
        let project: ProjectID
        let header: CGRect
        let rows: [(id: SessionID, frame: CGRect)]
    }

    /// The target under `point`, or nil when the pointer is off the list: beside it, above the
    /// first project, or more than a row below the last one (dropping there cancels).
    /// `sections` are in sidebar order; the dragged session's own row is ignored.
    static func at(_ point: CGPoint, width: CGFloat, sections: [Section], dragging: SessionID) -> SidebarDropTarget? {
        guard point.x >= 0, point.x <= width, let first = sections.first, let lastSection = sections.last,
              point.y >= first.header.minY - slack,
              point.y <= (lastSection.rows.last?.frame.maxY ?? lastSection.header.maxY) + 28 else { return nil }
        // The last section whose header starts above the pointer; above them all, the first.
        let section = sections.last { $0.header.minY <= point.y } ?? first
        let rows = section.rows.filter { $0.id != dragging }
        let index = rows.filter { $0.frame.midY < point.y }.count
        let lineY: CGFloat
        if index < rows.count {
            lineY = rows[index].frame.minY - 1
        } else if let last = rows.last {
            lineY = last.frame.maxY + 1
        } else {
            lineY = section.header.maxY + 1
        }
        return SidebarDropTarget(project: section.project, index: index, lineY: lineY)
    }

    /// How far above the first header still counts as the top of the list.
    static let slack: CGFloat = 8
}
