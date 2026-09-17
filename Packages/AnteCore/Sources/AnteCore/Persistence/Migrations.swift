import Foundation

/// Forward-only JSON migrations for `state.json`, keyed by the schema version they migrate *from*.
/// Each step mutates the raw dictionary and must set `schemaVersion` to the version it produces.
public struct Migrations: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    public let steps: [Int: Step]

    public init(steps: [Int: Step]) {
        self.steps = steps
    }

    /// The real registry. Empty at schema version 1; add `0: { ... }`-style entries as the schema evolves.
    public static let current = Migrations(steps: [:])

    public func step(from version: Int) -> Step? {
        steps[version]
    }
}
