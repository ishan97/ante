// Packages/AnteCore/Sources/AnteCore/Config/ConfigWatcher.swift
import Foundation
import os

/// Reloads `config.toml` when it changes. Watches the *directory* (editors that save by writing
/// a temp file and renaming over the original) and the *file* (editors that write in place, like
/// VS Code); the file watch is re-armed after every reload because a rename replaces the inode.
@MainActor
public final class ConfigWatcher {
    private static let logger = Logger(subsystem: "ante.term", category: "config")

    private let paths: AppPaths
    private let loader: ConfigLoader
    private let debounce: Duration
    private let onChange: @MainActor (ConfigLoadResult) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    public init(paths: AppPaths, loader: ConfigLoader = ConfigLoader(), debounce: Duration = .milliseconds(150),
                onChange: @escaping @MainActor (ConfigLoadResult) -> Void) {
        self.paths = paths
        self.loader = loader
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        stop()
        try? FileManager.default.createDirectory(at: paths.configRoot, withIntermediateDirectories: true)
        descriptor = open(paths.configRoot.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("cannot watch \(self.paths.configRoot.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .rename, .delete, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        self.source = source
        armFileWatch()
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
        fileSource?.cancel()
        fileSource = nil
    }

    /// Watches the config file's current inode for in-place writes.
    private func armFileWatch() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(paths.configFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func scheduleReload() {
        pending?.cancel()
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.onChange(self.loader.load(from: self.paths.configFile))
            self.armFileWatch()
        }
    }
}
