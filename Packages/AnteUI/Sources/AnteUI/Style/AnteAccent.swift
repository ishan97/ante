// Packages/AnteUI/Sources/AnteUI/Style/AnteAccent.swift
import SwiftUI
import AppKit
import AnteCore

private struct AnteAccentKey: EnvironmentKey {
    static let defaultValue: Color = AnteStyle.defaultAccent
}

extension EnvironmentValues {
    /// The chrome accent: focus ring, waiting badges, palette selection. Injected at each window's
    /// root from the config so a change repaints everything without a relaunch.
    public var anteAccent: Color {
        get { self[AnteAccentKey.self] }
        set { self[AnteAccentKey.self] = newValue }
    }
}

public enum AnteAccent {
    /// Presets offered in Settings; the first is the default.
    public static let presets: [(name: String, hex: String)] = [
        ("Amber", AnteStyle.defaultAccentHex), ("Sky", "#6EA8FF"), ("Mint", "#7ADA8F"), ("Rose", "#FF7A9E"),
        ("Violet", "#B388FF"), ("Teal", "#5FD4C9"), ("Graphite", "#B8BCC6"),
    ]

    public static func color(for hex: String?) -> Color {
        guard let hex, let c = HexColor.parse(hex) else { return AnteStyle.defaultAccent }
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }

    public static func hex(for color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return HexColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)).hex
    }
}
