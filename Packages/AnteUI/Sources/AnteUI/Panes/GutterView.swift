// Packages/AnteUI/Sources/AnteUI/Panes/GutterView.swift
import SwiftUI
import AnteTerm

/// A narrow strip on the pane's left edge with one dot per prompt: green ok, red failed, dim for
/// unknown. Click a dot to scroll that command to the top.
struct GutterView: View {
    let controller: TerminalSessionController

    var body: some View {
        // Reading contentVersion subscribes this view to scroll/output changes.
        let _ = controller.contentVersion
        let cell = controller.view.cellSize()
        let top = controller.topVisibleRow
        let visible = top..<(top + controller.rows)
        // Only the visible rows are scanned: a dozen dots at most, diffed by row, so output at
        // 30 Hz moves circles instead of rebuilding the view.
        let marks = controller.marks(in: visible)
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(marks, id: \.row) { mark in
                Circle()
                    .fill(color(for: mark.exitCode))
                    .frame(width: 6, height: 6)
                    .offset(x: 3, y: CGFloat(mark.row - top) * cell.height + cell.height / 2 - 3)
            }
        }
        .frame(width: 12)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { location in
            let row = top + Int(location.y / max(cell.height, 1))
            if let mark = marks.min(by: { abs($0.row - row) < abs($1.row - row) }), abs(mark.row - row) <= 1 {
                controller.view.scrollTo(row: mark.row)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for exitCode: Int?) -> Color {
        switch exitCode {
        case .some(0): return AnteStyle.statusOK
        case .some: return AnteStyle.statusFailed
        case .none: return AnteStyle.textSecondary.opacity(0.5)
        }
    }
}
