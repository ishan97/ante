// Packages/AnteUI/Sources/AnteUI/Panes/SplitContainerView.swift
import SwiftUI

/// Renders a `SplitTree`. Dividers are draggable; the ratio is written back to the runtime.
struct SplitContainerView: View {
    @Bindable var runtime: WorkspaceRuntime
    let tree: SplitTree

    var body: some View {
        switch tree {
        case let .leaf(pane):
            TerminalPaneView(
                controller: runtime.controller(for: pane),
                isFocused: runtime.focusedPaneID == pane,
                onFocus: { runtime.focusPane(pane) },
                showSearch: runtime.isSearchVisible && runtime.focusedPaneID == pane,
                onCloseSearch: { runtime.isSearchVisible = false },
                showClose: runtime.session(for: pane).map { runtime.paneCount(for: $0) > 1 } ?? false,
                onClose: { runtime.closePane(pane) }
            )
            // Keyed by pane: an NSViewRepresentable cannot swap its hosted NSView in
            // updateNSView, so switching sessions must create a fresh host per pane.
            .id(pane)
        case let .split(axis, ratio, first, second):
            GeometryReader { proxy in
                let total = axis == .horizontal ? proxy.size.width : proxy.size.height
                let firstSize = max(120, min(total - 120, total * ratio))
                let layout: AnyLayout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    SplitContainerView(runtime: runtime, tree: first)
                        .frame(width: axis == .horizontal ? firstSize : nil, height: axis == .vertical ? firstSize : nil)
                    SplitDivider(axis: axis) { delta in
                        let next = (firstSize + delta) / total
                        if let pane = first.paneIDs.first {
                            runtime.setRatio(min(0.85, max(0.15, next)), forSplitContaining: pane)
                        }
                    }
                    SplitContainerView(runtime: runtime, tree: second)
                }
            }
        }
    }
}

private struct SplitDivider: View {
    let axis: SplitAxis
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: axis == .horizontal ? 6 : nil, height: axis == .vertical ? 6 : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onDrag(axis == .horizontal ? value.translation.width : value.translation.height)
                    }
            )
    }
}
