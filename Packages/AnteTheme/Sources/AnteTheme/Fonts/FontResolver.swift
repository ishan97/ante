// Packages/AnteTheme/Sources/AnteTheme/Fonts/FontResolver.swift
import AppKit

/// Turns a configured family name into an `NSFont`, falling back through good monospace choices.
public enum FontResolver {
    public static let fallbackChain = ["JetBrains Mono", "FiraCode Nerd Font Mono", "SF Mono", "Menlo"]

    @MainActor
    public static func resolve(family: String, size: Double) -> NSFont {
        let candidates = [family] + fallbackChain
        for candidate in candidates where !candidate.isEmpty {
            if let font = font(family: candidate, size: size), font.isFixedPitch {
                return withSymbolFallbacks(font, size: size)
            }
        }
        return withSymbolFallbacks(NSFont.monospacedSystemFont(ofSize: size, weight: .regular), size: size)
    }

    /// Installed Nerd Fonts (and Apple's symbol fonts) as a cascade list, so prompt and `ls` icons
    /// in the private-use range render even when the main font lacks them. Mono variants first.
    @MainActor private static var cachedFallbacks: [String]?

    @MainActor
    public static func symbolFallbackFamilies() -> [String] {
        if let cachedFallbacks { return cachedFallbacks }
        let result = computeSymbolFallbackFamilies()
        cachedFallbacks = result
        return result
    }

    @MainActor
    private static func computeSymbolFallbackFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
        let nerd = families.filter { $0.localizedCaseInsensitiveContains("Nerd Font") }
            .sorted { a, b in
                let am = a.hasSuffix("Mono"), bm = b.hasSuffix("Mono")
                return am != bm ? am : a < b
            }
        let symbols = families.filter { $0 == "Symbols Nerd Font Mono" || $0 == "Symbols Nerd Font" }
        return Array(NSOrderedSet(array: symbols + nerd + ["Apple Symbols", "Apple Color Emoji"])) as? [String] ?? nerd
    }

    @MainActor
    private static func withSymbolFallbacks(_ font: NSFont, size: Double) -> NSFont {
        let fallbacks = symbolFallbackFamilies().filter { $0 != font.familyName }
        guard !fallbacks.isEmpty else { return font }
        let cascade = fallbacks.map { NSFontDescriptor(fontAttributes: [.family: $0]) }
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: cascade])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    @MainActor
    private static func font(family: String, size: Double) -> NSFont? {
        if let direct = NSFont(name: family, size: size) { return direct }
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else { return nil }
        // Prefer the regular face: weight 5, non-italic (trait 0).
        let regular = members.first { ($0[2] as? Int) == 5 && ($0[3] as? Int) == 0 } ?? members[0]
        guard let postScriptName = regular[0] as? String else { return nil }
        return NSFont(name: postScriptName, size: size)
    }
}
