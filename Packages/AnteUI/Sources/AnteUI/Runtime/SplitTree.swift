// Packages/AnteUI/Sources/AnteUI/Runtime/SplitTree.swift
import Foundation

public struct PaneID: Hashable, Sendable {
    public let rawValue: UUID
    public init() { rawValue = UUID() }
}

public enum SplitAxis: Sendable, Equatable {
    /// Panes side by side.
    case horizontal
    /// Panes stacked.
    case vertical
}

public enum PaneDirection: Sendable, Equatable {
    case left, right, up, down
}

/// A binary tree of panes. `ratio` is the fraction of space the `first` child gets.
public indirect enum SplitTree: Sendable, Equatable {
    case leaf(PaneID)
    case split(SplitAxis, ratio: Double, first: SplitTree, second: SplitTree)

    public var paneIDs: [PaneID] {
        switch self {
        case let .leaf(id): return [id]
        case let .split(_, _, first, second): return first.paneIDs + second.paneIDs
        }
    }

    public func contains(_ id: PaneID) -> Bool {
        paneIDs.contains(id)
    }

    /// Replaces `pane` with a split of `pane` and `newPane`. The new pane goes on the right /
    /// bottom, or on the left / top when `before` is true.
    public func splitting(pane: PaneID, axis: SplitAxis, newPane: PaneID, before: Bool = false) -> SplitTree {
        switch self {
        case let .leaf(id):
            guard id == pane else { return self }
            return before
                ? .split(axis, ratio: 0.5, first: .leaf(newPane), second: .leaf(id))
                : .split(axis, ratio: 0.5, first: .leaf(id), second: .leaf(newPane))
        case let .split(a, ratio, first, second):
            return .split(a, ratio: ratio,
                          first: first.splitting(pane: pane, axis: axis, newPane: newPane, before: before),
                          second: second.splitting(pane: pane, axis: axis, newPane: newPane, before: before))
        }
    }

    /// Removes a pane; a split with one remaining child collapses into that child. Nil when empty.
    public func removing(pane: PaneID) -> SplitTree? {
        switch self {
        case let .leaf(id):
            return id == pane ? nil : self
        case let .split(axis, ratio, first, second):
            let f = first.removing(pane: pane)
            let s = second.removing(pane: pane)
            switch (f, s) {
            case let (f?, s?): return .split(axis, ratio: ratio, first: f, second: s)
            case let (f?, nil): return f
            case let (nil, s?): return s
            case (nil, nil): return nil
            }
        }
    }

    public func withRatio(_ ratio: Double, forSplitContaining pane: PaneID) -> SplitTree {
        switch self {
        case .leaf: return self
        case let .split(axis, old, first, second):
            if case .leaf(let id) = first, id == pane { return .split(axis, ratio: ratio, first: first, second: second) }
            if case .leaf(let id) = second, id == pane { return .split(axis, ratio: ratio, first: first, second: second) }
            return .split(axis, ratio: old,
                          first: first.withRatio(ratio, forSplitContaining: pane),
                          second: second.withRatio(ratio, forSplitContaining: pane))
        }
    }

    /// The pane you land on when pressing an arrow from `pane`: the nearest ancestor split along
    /// the matching axis where `pane` sits on the near side; then the closest leaf on the far side.
    public func neighbor(of pane: PaneID, direction: PaneDirection) -> PaneID? {
        var result: PaneID?
        _ = walk(pane: pane, direction: direction, result: &result)
        return result
    }

    private func walk(pane: PaneID, direction: PaneDirection, result: inout PaneID?) -> Bool {
        switch self {
        case let .leaf(id):
            return id == pane
        case let .split(axis, _, first, second):
            let inFirst = first.walk(pane: pane, direction: direction, result: &result)
            let inSecond = !inFirst && second.walk(pane: pane, direction: direction, result: &result)
            guard inFirst || inSecond, result == nil else { return inFirst || inSecond }
            let wanted: SplitAxis = (direction == .left || direction == .right) ? .horizontal : .vertical
            guard axis == wanted else { return true }
            switch (direction, inFirst) {
            case (.right, true), (.down, true): result = second.edgeLeaf(near: true)
            case (.left, false), (.up, false): result = first.edgeLeaf(near: false)
            default: break
            }
            return true
        }
    }

    /// `near: true` → the first leaf (top/left edge); `false` → the last leaf (bottom/right edge).
    private func edgeLeaf(near: Bool) -> PaneID {
        switch self {
        case let .leaf(id): return id
        case let .split(_, _, first, second): return near ? first.edgeLeaf(near: true) : second.edgeLeaf(near: false)
        }
    }
}
