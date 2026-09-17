import Foundation

/// One Operating System Command extracted from the PTY stream: `ESC ] <code> ; <payload> BEL|ST`.
public struct OSCSequence: Equatable, Sendable {
    public let code: Int
    public let payload: [UInt8]

    public init(code: Int, payload: [UInt8]) {
        self.code = code
        self.payload = payload
    }

    /// Parses `<digits>[;<payload>]`. Returns nil when there are no leading digits.
    static func parse(_ raw: [UInt8]) -> OSCSequence? {
        var index = 0
        var code = 0
        var sawDigit = false
        while index < raw.count, raw[index] >= 0x30, raw[index] <= 0x39 {
            code = code * 10 + Int(raw[index] - 0x30)
            sawDigit = true
            index += 1
            if code > 99_999 { return nil }
        }
        guard sawDigit else { return nil }
        if index < raw.count {
            guard raw[index] == 0x3B else { return nil } // ';'
            index += 1
        }
        return OSCSequence(code: code, payload: Array(raw[index...]))
    }
}

/// Pulls OSC sequences out of a raw terminal byte stream without interpreting anything else.
///
/// Rules:
/// 1. An OSC starts with `ESC ]` and ends with `BEL` (0x07) or `ESC \` (ST).
/// 2. State survives across `scan` calls, so sequences split across PTY reads are reassembled.
/// 3. Any C0 control other than BEL and ESC inside an OSC aborts it. No real OSC contains a raw
///    newline, and this stops a stray `ESC ]` from swallowing the rest of the output.
/// 4. Payloads over `maxPayloadBytes` are dropped, so a hostile program cannot grow the buffer forever.
/// 5. The code is the leading run of ASCII digits; a following `;` is consumed. No digits → dropped.
public struct OSCScanner: Sendable {
    public static let maxPayloadBytes = 65_536

    private enum State { case ground, escape, osc, oscEscape }

    private var state: State = .ground
    private var buffer: [UInt8] = []
    private var overflowed = false

    public init() {}

    public mutating func scan(_ bytes: ArraySlice<UInt8>) -> [OSCSequence] {
        scanWithEnds(bytes).map(\.sequence)
    }

    /// Like `scan`, but each sequence comes with the offset (relative to `bytes.startIndex`) just
    /// past its terminator, so a caller can feed the bytes up to an event before acting on it.
    public mutating func scanWithEnds(_ bytes: ArraySlice<UInt8>) -> [(sequence: OSCSequence, end: Int)] {
        var found: [(sequence: OSCSequence, end: Int)] = []
        for (offset, byte) in bytes.enumerated() {
            switch state {
            case .ground:
                if byte == 0x1B { state = .escape }

            case .escape:
                switch byte {
                case 0x5D: beginOSC()          // ']'
                case 0x1B: state = .escape     // ESC ESC: stay armed
                default: state = .ground
                }

            case .osc:
                switch byte {
                case 0x07: finish(into: &found, end: offset + 1)
                case 0x1B: state = .oscEscape
                case 0x00..<0x20: state = .ground   // rule 3
                default: append(byte)
                }

            case .oscEscape:
                switch byte {
                case 0x5C: finish(into: &found, end: offset + 1)     // ESC \  (ST)
                case 0x5D: beginOSC()               // ESC ]  a new OSC started inside a broken one
                default: state = .ground
                }
            }
        }
        return found
    }

    private mutating func beginOSC() {
        state = .osc
        buffer.removeAll(keepingCapacity: true)
        overflowed = false
    }

    private mutating func append(_ byte: UInt8) {
        if buffer.count < Self.maxPayloadBytes {
            buffer.append(byte)
        } else {
            overflowed = true
        }
    }

    private mutating func finish(into found: inout [(sequence: OSCSequence, end: Int)], end: Int) {
        defer {
            state = .ground
            buffer.removeAll(keepingCapacity: true)
            overflowed = false
        }
        guard !overflowed, let sequence = OSCSequence.parse(buffer) else { return }
        found.append((sequence, end))
    }
}
