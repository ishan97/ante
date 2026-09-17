// Packages/AnteCore/Sources/AnteCore/Config/ConfigEditor.swift
import Foundation

/// Edits `config.toml` one key at a time by rewriting lines, so comments and keys Ante does not
/// know about survive. Handles the flat `[section]` / `key = value` shape Ante's config uses;
/// anything more exotic in the file is left untouched.
public struct ConfigEditor: Sendable {
    public enum Value: Equatable, Sendable {
        case string(String)
        case bool(Bool)
        case int(Int)
        case double(Double)
        case stringArray([String])

        var toml: String {
            switch self {
            case let .string(s): return "\"\(Self.escape(s))\""
            case let .bool(b): return b ? "true" : "false"
            case let .int(i): return String(i)
            case let .double(d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
            case let .stringArray(a): return "[" + a.map { "\"\(Self.escape($0))\"" }.joined(separator: ", ") + "]"
            }
        }

        private static func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
    }

    public struct WriteError: Error, Equatable, Sendable {
        public let message: String
    }

    public let paths: AppPaths
    private let loader: ConfigLoader

    public init(paths: AppPaths, loader: ConfigLoader = ConfigLoader()) {
        self.paths = paths
        self.loader = loader
    }

    /// Reads the file (or starts empty), applies the edit, validates, and writes atomically.
    public func write(section: String, key: String, value: Value) throws {
        let current: String
        if FileManager.default.fileExists(atPath: paths.configFile.path) {
            // An existing file that cannot be read must not be mistaken for an empty one, or the
            // next write would replace every setting the user has with this single key.
            guard let text = try? String(contentsOf: paths.configFile, encoding: .utf8) else {
                throw WriteError(message: "config.toml exists but could not be read as UTF-8; not overwriting it")
            }
            current = text
        } else {
            current = ""
        }
        let edited = Self.set(current, section: section, key: key, value: value)
        do {
            _ = try loader.parse(edited)
        } catch let error as ConfigError {
            throw WriteError(message: "refusing to write a config that no longer parses: \(error.message)")
        }
        try AtomicFile.write(Data(edited.utf8), to: paths.configFile)
    }

    /// Pure text transformation. Sections are matched by exact `[name]` header; keys by
    /// `key =` at the start of a line (leading whitespace allowed).
    public static func set(_ toml: String, section: String, key: String, value: Value) -> String {
        var lines = toml.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }   // keep track of the trailing newline ourselves
        let assignment = "\(key) = \(value.toml)"

        guard let headerIndex = lines.firstIndex(where: { isHeader($0, section) }) else {
            var out = lines
            if !out.isEmpty { out.append("") }
            out.append("[\(section)]")
            out.append(assignment)
            return out.joined(separator: "\n") + "\n"
        }

        var end = lines.count
        for index in (headerIndex + 1)..<lines.count where isAnyHeader(lines[index]) {
            end = index
            break
        }
        for index in (headerIndex + 1)..<end where isAssignment(lines[index], key) {
            lines[index] = assignment
            return lines.joined(separator: "\n") + "\n"
        }
        // Insert before the blank lines that pad the next section, if any.
        var insertAt = end
        while insertAt > headerIndex + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        lines.insert(assignment, at: insertAt)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func isHeader(_ line: String, _ section: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "[\(section)]"
    }

    private static func isAnyHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("[") && t.hasSuffix("]")
    }

    private static func isAssignment(_ line: String, _ key: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key) else { return false }
        let rest = t.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return rest.hasPrefix("=")
    }
}
