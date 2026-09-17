// Packages/AnteTheme/Sources/AnteTheme/Fonts/FontRegistrar.swift
import Foundation
import CoreText
import os

/// Registers the bundled JetBrains Mono faces for this process only. Never installs system-wide.
public enum FontRegistrar {
    private static let logger = Logger(subsystem: "ante.term", category: "fonts")
    nonisolated(unsafe) private static var registered = false

    @MainActor
    public static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        guard let directory = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            logger.error("bundled fonts directory missing")
            return
        }
        for url in files where url.pathExtension == "ttf" {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let description = error?.takeRetainedValue().localizedDescription ?? "unknown"
                // "already registered" is expected when tests re-run in one process.
                if !description.contains("already") {
                    logger.error("font registration failed for \(url.lastPathComponent, privacy: .public): \(description, privacy: .public)")
                }
            }
        }
    }
}
