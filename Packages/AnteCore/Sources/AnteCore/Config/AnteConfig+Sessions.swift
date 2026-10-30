// Packages/AnteCore/Sources/AnteCore/Config/AnteConfig+Sessions.swift
import Foundation

extension AnteConfig {
    /// `[sessions]`: what happens to the sidebar's sessions when Ante quits.
    public struct Sessions: Equatable, Sendable, Decodable {
        /// Reopen every session as it was — names, folders, splits, agents resumed — instead of
        /// filing them into History and starting with one fresh session.
        public var restore: Bool = false

        public init() {}

        private enum CodingKeys: String, CodingKey { case restore }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            restore = try c.decodeIfPresent(Bool.self, forKey: .restore) ?? restore
        }
    }
}
