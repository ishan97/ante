// Packages/AnteTerm/Sources/AnteTerm/View/LinkDetector.swift
import Foundation

/// Finds things worth ⌘-clicking in one row of terminal text: URLs with an allowed scheme, and
/// file paths that exist (optionally with `:line[:col]`).
public enum LinkDetector {
    public enum Kind: Equatable, Sendable {
        case url(URL)
        case path(String, line: Int?)
    }

    public struct Match: Equatable, Sendable {
        /// Column range within the line (unicode scalars ≈ cells for ASCII; wide chars are rare in links).
        public let range: Range<Int>
        public let kind: Kind

        public init(range: Range<Int>, kind: Kind) {
            self.range = range
            self.kind = kind
        }
    }

    public static let allowedSchemes: Set<String> = ["http", "https", "mailto", "file"]

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:https?://|mailto:|file:///)[^\s<>"'()\[\]{}]+"#)
    private static let pathRegex = try! NSRegularExpression(
        pattern: #"(?:~|\.{1,2})?/[^\s:"'<>()\[\]{}]+(?::(\d+)(?::\d+)?)?"#)

    /// `relativeTo` is the directory `./` and `../` paths are resolved against (the pane's working
    /// directory); without it, relative paths are not linked at all, since the app's own working
    /// directory has nothing to do with what the shell printed.
    public static func detect(in line: String, relativeTo base: URL? = nil,
                              fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Match] {
        let ns = line as NSString
        var matches: [Match] = []

        for m in urlRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            var text = ns.substring(with: m.range)
            var length = m.range.length
            while let last = text.last, ".,;:!?".contains(last) {   // trailing punctuation
                text.removeLast(); length -= 1
            }
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { continue }
            matches.append(Match(range: m.range.location..<(m.range.location + length), kind: .url(url)))
        }

        for m in pathRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let whole = ns.substring(with: m.range)
            if matches.contains(where: { $0.range.overlaps(m.range.location..<(m.range.location + m.range.length)) }) { continue }
            var path = whole
            var lineNumber: Int?
            if m.range(at: 1).location != NSNotFound {
                lineNumber = Int(ns.substring(with: m.range(at: 1)))
                path = String(whole[..<whole.range(of: ":\(ns.substring(with: m.range(at: 1)))")!.lowerBound])
            }
            var expanded = (path as NSString).expandingTildeInPath
            if path.hasPrefix(".") {
                guard let base else { continue }
                expanded = base.appendingPathComponent(path).standardizedFileURL.path
            }
            guard fileExists(expanded) else { continue }
            matches.append(Match(range: m.range.location..<(m.range.location + m.range.length), kind: .path(expanded, line: lineNumber)))
        }
        return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    public static func match(in line: String, atColumn column: Int, relativeTo base: URL? = nil) -> Match? {
        detect(in: line, relativeTo: base).first { $0.range.contains(column) }
    }
}
