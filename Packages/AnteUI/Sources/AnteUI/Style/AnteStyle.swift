// Packages/AnteUI/Sources/AnteUI/Style/AnteStyle.swift
import SwiftUI
import AppKit

/// Ante's chrome tokens. Dark and light are both first-class; the terminal palette is separate
/// (that's the theme), these are for the sidebar, toolbar, and overlays.
public enum AnteStyle {
    /// Ante's amber. The live accent is `@Environment(\.anteAccent)`, set from `[theme] accent`.
    public static let defaultAccentHex = "#F5C56B"
    public static let defaultAccent = Color(nsColor: NSColor(srgbRed: 245/255, green: 197/255, blue: 107/255, alpha: 1))   // #F5C56B

    public static let sidebarBackground = dynamic(dark: (0.055, 0.063, 0.082), light: (0.965, 0.962, 0.953))
    public static let toolbarBackground = dynamic(dark: (0.043, 0.051, 0.071), light: (0.98, 0.978, 0.972))
    public static let paneBackground = dynamic(dark: (0.043, 0.051, 0.071), light: (0.98, 0.98, 0.97))
    public static let hairline = dynamic(dark: (1, 1, 1), light: (0, 0, 0), darkAlpha: 0.08, lightAlpha: 0.10)
    /// Clearly lighter than the sidebar in dark mode: the selected session must read at a glance,
    /// also through a translucent window.
    public static let rowSelected = dynamic(dark: (1, 1, 1), light: (0, 0, 0), darkAlpha: 0.24, lightAlpha: 0.09)
    public static let rowHover = dynamic(dark: (1, 1, 1), light: (0, 0, 0), darkAlpha: 0.10, lightAlpha: 0.05)
    public static let textPrimary = dynamic(dark: (0.96, 0.97, 0.98), light: (0.12, 0.14, 0.19))
    public static let textSecondary = dynamic(dark: (0.74, 0.77, 0.82), light: (0.42, 0.45, 0.52))
    public static let statusRunning = Color(nsColor: NSColor(srgbRed: 0.43, green: 0.66, blue: 1.0, alpha: 1))
    public static let statusOK = Color(nsColor: NSColor(srgbRed: 0.48, green: 0.85, blue: 0.56, alpha: 1))
    public static let statusFailed = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.42, alpha: 1))
    public static let statusExited = dynamic(dark: (0.45, 0.48, 0.55), light: (0.6, 0.62, 0.68))

    public static let sidebarWidth: CGFloat = 232
    public static let toolbarHeight: CGFloat = 38
    public static let paneInset: CGFloat = 8
    public static let radius: CGFloat = 7

    public static let uiFont = Font.system(size: 12.5, weight: .regular)
    public static let uiFontSemibold = Font.system(size: 12.5, weight: .semibold)
    public static let captionFont = Font.system(size: 10.5, weight: .medium)
    public static let monoCaption = Font.system(size: 11, design: .monospaced)

    private static func dynamic(dark: (Double, Double, Double), light: (Double, Double, Double),
                                darkAlpha: Double = 1, lightAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}
