import Foundation
import os

/// Loads and saves `AppState`. Never throws on load: a bad file is backed up and the app
/// starts fresh with a `Notice` the UI can show as a banner.
public struct StateStore: Sendable {
    public enum Notice: Equatable, Sendable {
        case startedFresh(reason: String, backupURL: URL?)
        case migrated(from: Int, to: Int)
    }

    public struct LoadResult: Equatable, Sendable {
        public let state: AppState
        public let notice: Notice?
    }

    private static let logger = Logger(subsystem: "ante.term", category: "state")

    public let paths: AppPaths
    public let migrations: Migrations

    public init(paths: AppPaths, migrations: Migrations = .current) {
        self.paths = paths
        self.migrations = migrations
    }

    public func load() -> LoadResult {
        let url = paths.stateFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadResult(state: .empty, notice: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return startFresh(reason: "state file unreadable: \(error.localizedDescription)", suffix: "corrupt")
        }

        guard var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return startFresh(reason: "state file unreadable: not a JSON object", suffix: "corrupt")
        }

        let fileVersion = dict["schemaVersion"] as? Int ?? 0
        let target = AppState.currentSchemaVersion

        if fileVersion > target {
            return startFresh(reason: "state file is from a newer Ante (schema \(fileVersion), this build reads \(target))",
                              suffix: "v\(fileVersion)")
        }

        var version = fileVersion
        while version < target {
            guard let step = migrations.step(from: version) else {
                return startFresh(reason: "no migration registered from schema \(version)", suffix: "v\(version)")
            }
            do {
                try step(&dict)
            } catch {
                return startFresh(reason: "migration from schema \(version) failed: \(error.localizedDescription)",
                                  suffix: "v\(version)")
            }
            let next = dict["schemaVersion"] as? Int ?? (version + 1)
            guard next > version else {
                return startFresh(reason: "migration from schema \(version) did not advance the version", suffix: "v\(version)")
            }
            version = next
        }

        let state: AppState
        do {
            let migratedData = try JSONSerialization.data(withJSONObject: dict)
            state = try Self.decoder.decode(AppState.self, from: migratedData)
        } catch {
            return startFresh(reason: "state file unreadable: \(error.localizedDescription)", suffix: "corrupt")
        }

        if fileVersion < target {
            try? save(state)
            return LoadResult(state: state, notice: .migrated(from: fileVersion, to: target))
        }
        return LoadResult(state: state, notice: nil)
    }

    public func save(_ state: AppState) throws {
        let data = try Self.encoder.encode(state)
        try AtomicFile.write(data, to: paths.stateFile)
    }

    // MARK: - Private

    private func startFresh(reason: String, suffix: String) -> LoadResult {
        Self.logger.error("starting fresh: \(reason, privacy: .public)")
        let backup = paths.stateFile.appendingPathExtension("bak-\(suffix)")
        var backupURL: URL? = nil
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.moveItem(at: paths.stateFile, to: backup)
            backupURL = backup
        } catch {
            Self.logger.error("could not back up state file: \(error.localizedDescription, privacy: .public)")
        }
        return LoadResult(state: .empty, notice: .startedFresh(reason: reason, backupURL: backupURL))
    }

    /// ISO 8601 with fractional seconds: readable in the file, and precise to the millisecond so
    /// a save/load cycle does not drift a session's `createdAt`.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(dateStyle))
        }
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            do {
                return try dateStyle.parse(text)
            } catch {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "bad date: \(text)"))
            }
        }
        return d
    }
}
