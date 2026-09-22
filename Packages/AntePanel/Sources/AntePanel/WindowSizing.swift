// Packages/AntePanel/Sources/AntePanel/WindowSizing.swift
import Foundation

/// Where the workspace window goes at launch and when `[window]` changes. Pure geometry, so the
/// rules are testable without a screen.
public enum WindowSizing {
    /// The frame for a window that should take `widthFraction` × `heightFraction` of `visible`
    /// (the screen minus menu bar and Dock), never smaller than `minSize` nor larger than the
    /// screen. It keeps the top-left corner of `previous` when the result still fits there, so a
    /// resize does not also move the window; otherwise it is centred.
    public static func frame(fraction widthFraction: Double, _ heightFraction: Double,
                             in visible: CGRect, previous: CGRect?, minSize: CGSize) -> CGRect {
        let w = min(visible.width, max(minSize.width, (visible.width * widthFraction).rounded()))
        let h = min(visible.height, max(minSize.height, (visible.height * heightFraction).rounded()))
        if let previous {
            let topLeft = CGPoint(x: previous.minX, y: previous.maxY)
            let candidate = CGRect(x: topLeft.x, y: topLeft.y - h, width: w, height: h)
            if visible.contains(candidate) { return candidate }
        }
        return CGRect(x: (visible.midX - w / 2).rounded(), y: (visible.midY - h / 2).rounded(), width: w, height: h)
    }
}
