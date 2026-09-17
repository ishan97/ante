import Foundation
import TOMLKit

/// A config problem the UI can show in a banner. `line` is 1-based when known.
public struct ConfigError: Error, Equatable, Sendable {
    public let line: Int?
    public let message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }
}

public enum ConfigLoadResult: Equatable, Sendable {
    case loaded(AnteConfig)
    case missing(AnteConfig)
    case failed(AnteConfig, ConfigError)

    /// The config to run with regardless of outcome.
    public var config: AnteConfig {
        switch self {
        case let .loaded(c), let .missing(c), let .failed(c, _): return c
        }
    }
}

public struct ConfigLoader: Sendable {
    public init() {}

    public func parse(_ toml: String) throws -> AnteConfig {
        do {
            // strictDecoding stays false so unknown keys from newer versions are ignored.
            return try TOMLDecoder().decode(AnteConfig.self, from: toml)
        } catch let error as TOMLParseError {
            throw ConfigError(line: error.source.begin.line, message: error.description)
        } catch let error as DecodingError {
            throw ConfigError(line: nil, message: Self.describe(error))
        } catch {
            throw ConfigError(line: nil, message: String(describing: error))
        }
    }

    public func load(from url: URL) -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing(.default)
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return .loaded(try parse(text))
        } catch let error as ConfigError {
            return .failed(.default, error)
        } catch {
            return .failed(.default, ConfigError(line: nil, message: error.localizedDescription))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .typeMismatch(type, context):
            return "expected \(type) at \(path(context)): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "missing \(type) at \(path(context))"
        case let .keyNotFound(key, context):
            return "missing key \(key.stringValue) at \(path(context))"
        case let .dataCorrupted(context):
            return "invalid value at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let p = context.codingPath.map(\.stringValue).joined(separator: ".")
        return p.isEmpty ? "top level" : p
    }
}
