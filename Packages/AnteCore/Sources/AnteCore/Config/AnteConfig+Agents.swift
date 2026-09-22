// Packages/AnteCore/Sources/AnteCore/Config/AnteConfig+Agents.swift
import Foundation

extension AnteConfig {
    public struct Agents: Equatable, Sendable, Decodable {
        /// An agent that has printed nothing for this long is shown as "waiting for you (probably)".
        public var quietSeconds: Double = 8
        /// Post a macOS notification when a session moves into "waiting for you".
        public var notify: Bool = true
        /// A system sound name (`/System/Library/Sounds`, e.g. "Glass"); empty for silent.
        public var notifySound: String = "Glass"

        public init() {}

        private enum CodingKeys: String, CodingKey { case quietSeconds = "quiet_seconds", notify, notifySound = "notify_sound" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            quietSeconds = try c.decodeNumberIfPresent(forKey: .quietSeconds) ?? quietSeconds
            notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? notify
            notifySound = try c.decodeIfPresent(String.self, forKey: .notifySound) ?? notifySound
        }
    }
}
