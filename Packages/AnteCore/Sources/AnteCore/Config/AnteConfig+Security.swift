// Packages/AnteCore/Sources/AnteCore/Config/AnteConfig+Security.swift
import Foundation

extension AnteConfig {
    public struct Security: Equatable, Sendable, Decodable {
        /// Show a confirmation before pasting text that contains a newline.
        public var confirmMultilinePaste: Bool = true

        public init() {}

        private enum CodingKeys: String, CodingKey { case confirmMultilinePaste = "confirm_multiline_paste" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            confirmMultilinePaste = try c.decodeIfPresent(Bool.self, forKey: .confirmMultilinePaste) ?? confirmMultilinePaste
        }
    }

}
