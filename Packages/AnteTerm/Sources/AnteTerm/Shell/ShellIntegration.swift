import Foundation

/// Where the shell integration files were materialized for this app version.
public struct InstalledIntegration: Equatable, Sendable {
    public let root: URL
    public let zshDirectory: URL
    public let bashInitFile: URL
    public let fishInitFile: URL
    /// Holds the `claude` and `codex` launchers; the integrations put it first on PATH.
    public let binDirectory: URL
}

/// Copies the bundled integration scripts into a directory the shells can read, using their
/// real dotfile names. The bundle stores them without leading dots so tooling never hides them.
public enum ShellIntegration {
    public enum InstallError: Error {
        case bundleResourceMissing(String)
    }

    private static let zshFiles: [(resource: String, installed: String)] = [
        ("zshenv", ".zshenv"),
        ("zprofile", ".zprofile"),
        ("zshrc", ".zshrc"),
        ("ante-integration.zsh", "ante-integration.zsh"),
    ]

    public static func install(into root: URL, version: String) throws -> InstalledIntegration {
        guard let source = Bundle.module.url(forResource: "Integration", withExtension: nil) else {
            throw InstallError.bundleResourceMissing("Integration")
        }
        let fm = FileManager.default
        let versionRoot = root.appendingPathComponent(version, isDirectory: true)
        let zshDir = versionRoot.appendingPathComponent("zsh", isDirectory: true)
        let bashDir = versionRoot.appendingPathComponent("bash", isDirectory: true)
        let fishDir = versionRoot.appendingPathComponent("fish", isDirectory: true)
        let binDir = versionRoot.appendingPathComponent("bin", isDirectory: true)
        for dir in [zshDir, bashDir, fishDir, binDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        for file in zshFiles {
            try copy(source.appendingPathComponent("zsh/\(file.resource)"),
                     to: zshDir.appendingPathComponent(file.installed))
        }
        let bashInit = bashDir.appendingPathComponent("ante-bash.sh")
        try copy(source.appendingPathComponent("bash/ante-bash.sh"), to: bashInit)
        let fishInit = fishDir.appendingPathComponent("ante.fish")
        try copy(source.appendingPathComponent("fish/ante.fish"), to: fishInit)
        // One script, installed under each agent's name: it reads which agent it is from $0.
        for agent in ["claude", "codex"] {
            try copy(source.appendingPathComponent("bin/ante-launch"), to: binDir.appendingPathComponent(agent), mode: 0o755)
        }
        // Marks the directory as launchers, so a launcher never mistakes another Ante's for the agent.
        try Data().write(to: binDir.appendingPathComponent(".ante-launchers"), options: .atomic)

        return InstalledIntegration(root: versionRoot, zshDirectory: zshDir, bashInitFile: bashInit, fishInitFile: fishInit,
                                    binDirectory: binDir)
    }

    private static func copy(_ from: URL, to: URL, mode: Int = 0o644) throws {
        guard FileManager.default.fileExists(atPath: from.path) else {
            throw InstallError.bundleResourceMissing(from.lastPathComponent)
        }
        let data = try Data(contentsOf: from)
        try data.write(to: to, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: to.path)
    }
}
