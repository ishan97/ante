// Packages/AnteCore/Sources/AnteCore/Agents/JSONLines.swift
import Foundation

/// Reads the first `limit` bytes of a file and yields each complete JSON line as a dictionary.
enum JSONLines {
    static let limit = 64 * 1024

    static func head(of url: URL) -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limit)) ?? Data()
        return parse(data)
    }

    static func parse(_ data: Data) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for chunk in data.split(separator: 0x0A) {
            if let obj = (try? JSONSerialization.jsonObject(with: chunk)) as? [String: Any] { out.append(obj) }
        }
        return out
    }
}
