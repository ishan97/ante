// Packages/AnteCore/Sources/AnteCore/Config/HexColor.swift
import Foundation

/// `#RRGGBB` as unit-range components. The chrome accent in `[theme] accent` uses it.
public struct HexColor: Equatable, Sendable {
    public let red: Double, green: Double, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    public static func parse(_ text: String) -> HexColor? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return HexColor(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Perceived brightness, 0 (black) to 1 (white). Decides light or dark chrome text.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Nudges the colour toward white (factor > 1) or black (factor < 1) for sidebar/toolbar shades.
    public func shaded(_ factor: Double) -> HexColor {
        HexColor(red: min(red * factor, 1), green: min(green * factor, 1), blue: min(blue * factor, 1))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
