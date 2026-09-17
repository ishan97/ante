import Foundation
import AnteCore

/// Turns OSC 133 (semantic prompt, as used by iTerm2 / VS Code / Ghostty), OSC 7 (cwd) and
/// OSC 9 (notification) into `SemanticEvent`s. Everything else is ignored.
///
/// OSC 133 actions handled: `A` prompt start, `C` command start, `D[;exit]` command finished.
/// `B` (input start) and any other action are ignored on purpose.
public struct SemanticPromptParser: Sendable {
    public init() {}

    public func parse(all sequences: [OSCSequence]) -> [SemanticEvent] {
        sequences.compactMap(parse)
    }

    public func parse(_ sequence: OSCSequence) -> SemanticEvent? {
        switch sequence.code {
        case 133: return parseSemanticPrompt(sequence.payload)
        case 7: return parseWorkingDirectory(sequence.payload)
        case 9: return parseNotification(sequence.payload)
        default: return nil
        }
    }

    /// `OSC 9 ; <message>`. ConEmu progress (`9;4;<state>;<pct>`) shares the code and is skipped.
    private func parseNotification(_ payload: [UInt8]) -> SemanticEvent? {
        if payload.count >= 2, payload[0] == UInt8(ascii: "4"), payload[1] == UInt8(ascii: ";") { return nil }
        guard let text = String(bytes: payload, encoding: .utf8) else { return nil }
        let message = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        return .notification(String(message.prefix(200)))
    }

    private func parseSemanticPrompt(_ payload: [UInt8]) -> SemanticEvent? {
        let fields = payload.split(separator: 0x3B, omittingEmptySubsequences: false) // ';'
        guard let action = fields.first?.first else { return nil }
        switch action {
        case UInt8(ascii: "A"):
            return .promptStarted
        case UInt8(ascii: "C"):
            return .commandStarted
        case UInt8(ascii: "D"):
            guard fields.count > 1,
                  let text = String(bytes: fields[1], encoding: .utf8),
                  let code = Int(text) else {
                return .commandFinished(exitCode: nil)
            }
            return .commandFinished(exitCode: code)
        default:
            return nil
        }
    }

    /// This machine's names, from `gethostname(2)` (no DNS: this runs on the PTY read queue),
    /// resolved once.
    private static let localNames: Set<String> = {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return [] }
        let full = String(cString: buffer).lowercased()
        var names: Set<String> = [full]
        if let short = full.split(separator: ".").first { names.insert(String(short)) }
        return names
    }()

    /// Empty, `localhost`, or this machine's own name (with or without domain).
    static func isLocalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return true }
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        return localNames.contains(h) || localNames.contains(where: { $0.hasPrefix(h + ".") })
    }

    static func isLocalDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func parseWorkingDirectory(_ payload: [UInt8]) -> SemanticEvent? {
        guard let text = String(bytes: payload, encoding: .utf8),
              let url = URL(string: text),
              url.scheme?.lowercased() == "file" else {
            return nil
        }
        let path = url.path // percent-decoded
        guard path.hasPrefix("/") else { return nil }
        // A shell over ssh reports *its* cwd with *its* hostname. Hostnames are not a reliable
        // identity for this Mac (they change with the network), so an unfamiliar host is
        // accepted only when the directory exists here — a remote /home/ci/repo does not.
        guard Self.isLocalHost(url.host) || Self.isLocalDirectory(path) else { return nil }
        return .cwdChanged(URL(fileURLWithPath: path))
    }
}
