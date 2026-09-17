// Packages/AnteTheme/Sources/AnteTheme/ThemeColor.swift
import Foundation

/// An 8-bit sRGB colour. Parses `#RRGGBB`, `RRGGBB`, and Alacritty's `0xRRGGBB`.
public struct ThemeColor: Hashable, Sendable, Codable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        else if text.lowercased().hasPrefix("0x") { text.removeFirst(2) }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Perceived luminance 0…1, for deciding whether a background is dark.
    public var luminance: Double {
        (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = ThemeColor(hex: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad colour \(text)"))
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}
