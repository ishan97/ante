// Packages/AnteTheme/Sources/AnteTheme/ThemeLoader.swift
import Foundation
import os

/// Finds themes by file name (without `.toml`): the user's directory first, then the bundle.
/// `ante` is special: it resolves to `ante-dark` or `ante-light` by appearance.
public struct ThemeLoader: Sendable {
    private static let logger = Logger(subsystem: "ante.term", category: "theme")

    public let userDirectory: URL?
    private let bundledDirectory: URL?

    public init(userDirectory: URL?) {
        self.userDirectory = userDirectory
        self.bundledDirectory = Bundle.module.url(forResource: "Themes", withExtension: nil)
    }

    public var builtInNames: [String] {
        names(in: bundledDirectory)
    }

    public var availableNames: [String] {
        Array(Set(builtInNames + names(in: userDirectory))).sorted()
    }

    public func theme(named name: String) -> TerminalTheme? {
        for directory in [userDirectory, bundledDirectory].compactMap({ $0 }) {
            let url = directory.appendingPathComponent("\(name).toml")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            do {
                return try TerminalTheme.parse(toml: text)
            } catch {
                Self.logger.error("theme \(name, privacy: .public) unreadable: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return nil
    }

    public func resolve(name: String, preferDark: Bool) -> TerminalTheme {
        let candidate = name == "ante" ? (preferDark ? "ante-dark" : "ante-light") : name
        if let theme = theme(named: candidate) { return theme }
        return theme(named: preferDark ? "ante-dark" : "ante-light") ?? Self.emergency
    }

    private func names(in directory: URL?) -> [String] {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { $0.pathExtension == "toml" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// Used only if the bundle itself is broken; keeps the app usable.
    static let emergency = TerminalTheme(
        name: "Ante Dark", appearance: .dark,
        foreground: ThemeColor(red: 215, green: 220, blue: 229), background: ThemeColor(red: 11, green: 13, blue: 18),
        cursor: ThemeColor(red: 245, green: 197, blue: 107),
        selectionBackground: ThemeColor(red: 37, green: 54, blue: 84), selectionForeground: ThemeColor(red: 244, green: 246, blue: 250),
        ansi: [
            ThemeColor(red: 26, green: 29, blue: 38), ThemeColor(red: 255, green: 107, blue: 107),
            ThemeColor(red: 123, green: 216, blue: 143), ThemeColor(red: 245, green: 197, blue: 107),
            ThemeColor(red: 110, green: 168, blue: 254), ThemeColor(red: 199, green: 155, blue: 245),
            ThemeColor(red: 108, green: 212, blue: 212), ThemeColor(red: 201, green: 206, blue: 216),
            ThemeColor(red: 84, green: 90, blue: 104), ThemeColor(red: 255, green: 138, blue: 138),
            ThemeColor(red: 150, green: 230, blue: 168), ThemeColor(red: 255, green: 213, blue: 138),
            ThemeColor(red: 143, green: 188, blue: 255), ThemeColor(red: 216, green: 180, blue: 251),
            ThemeColor(red: 139, green: 226, blue: 226), ThemeColor(red: 232, green: 236, blue: 242),
        ]
    )
}
