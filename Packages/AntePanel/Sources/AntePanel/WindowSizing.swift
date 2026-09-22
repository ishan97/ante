// Packages/AntePanel/Sources/AntePanel/WindowSizing.swift
import Foundation

/// Where the workspace window goes at launch and when `[window]` changes. Pure geometry, so the
/// rules are testable without a screen.
public enum WindowSizing {
    /// The frame for a window that should take `widthFraction` × `heightFraction` of `visible`
    /// (the screen minus menu bar and Dock), anchored to the top-left corner of that area, never
    /// smaller than `minSize` nor larger than the screen.
    public static func frame(fraction widthFraction: Double, _ heightFraction: Double,
                             in visible: CGRect, minSize: CGSize) -> CGRect {
        let w = min(visible.width, max(minSize.width, (visible.width * widthFraction).rounded()))
        let h = min(visible.height, max(minSize.height, (visible.height * heightFraction).rounded()))
        return CGRect(x: visible.minX, y: visible.maxY - h, width: w, height: h)
    }
}
