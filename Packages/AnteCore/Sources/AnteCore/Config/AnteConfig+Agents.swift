// Packages/AnteCore/Sources/AnteCore/Config/AnteConfig+Agents.swift
import Foundation

extension AnteConfig {
    public struct Agents: Equatable, Sendable, Decodable {
        /// An agent that has printed nothing for this long is shown as "waiting for you (probably)".
        public var quietSeconds: Double = 8

        public init() {}

        private enum CodingKeys: String, CodingKey { case quietSeconds = "quiet_seconds" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            quietSeconds = try c.decodeNumberIfPresent(forKey: .quietSeconds) ?? quietSeconds
        }
    }
}
