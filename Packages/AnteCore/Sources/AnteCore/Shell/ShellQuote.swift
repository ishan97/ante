// Packages/AnteCore/Sources/AnteCore/Shell/ShellQuote.swift
import Foundation

/// Quotes paths for a POSIX shell so a dropped or picked file lands on the command line intact.
public enum ShellQuote {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./+:@%,=~")

    /// Bare when every character is shell-safe and the word cannot be misread (a leading `-` is an
    /// option, `~` and zsh's `=` expand); otherwise single-quoted, with `'` as `'\''`.
    public static func quote(_ text: String) -> String {
        if !text.isEmpty, text.allSatisfy({ safe.contains($0) }), !text.hasPrefix("-"), !text.hasPrefix("~"), !text.hasPrefix("=") { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The text to type for a set of files: each path quoted, space-separated, trailing space so
    /// the user can keep typing.
    public static func line(for urls: [URL]) -> String {
        let paths = urls.map { $0.standardizedFileURL.path }.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return "" }
        return paths.map(quote).joined(separator: " ") + " "
    }
}
