import XCTest
@testable import AnteTerm

final class ShellIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ante-int-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallMaterializesDotfilesUnderVersionDirectory() throws {
        let installed = try ShellIntegration.install(into: root, version: "0.1.0")
        XCTAssertEqual(installed.root, root.appendingPathComponent("0.1.0", isDirectory: true))
        let fm = FileManager.default
        for name in [".zshenv", ".zprofile", ".zshrc", "ante-integration.zsh"] {
            XCTAssertTrue(fm.fileExists(atPath: installed.zshDirectory.appendingPathComponent(name).path), name)
        }
        XCTAssertTrue(fm.fileExists(atPath: installed.bashInitFile.path))
        XCTAssertTrue(fm.fileExists(atPath: installed.fishInitFile.path))
        XCTAssertEqual(installed.bashInitFile.lastPathComponent, "ante-bash.sh")
        XCTAssertEqual(installed.fishInitFile.lastPathComponent, "ante.fish")
    }

    func testInstalledFilesEmitAllMarkers() throws {
        let installed = try ShellIntegration.install(into: root, version: "0.1.0")
        let files = [
            installed.zshDirectory.appendingPathComponent("ante-integration.zsh"),
            installed.bashInitFile,
            installed.fishInitFile,
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for marker in ["133;A", "133;B", "133;C", "133;D;", "]7;file://"] {
                XCTAssertTrue(text.contains(marker), "\(file.lastPathComponent) lacks \(marker)")
            }
        }
    }

    func testInstallIsIdempotentAndOverwrites() throws {
        let first = try ShellIntegration.install(into: root, version: "0.1.0")
        let target = first.zshDirectory.appendingPathComponent(".zshrc")
        try Data("tampered".utf8).write(to: target)
        let second = try ShellIntegration.install(into: root, version: "0.1.0")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(try String(contentsOf: target, encoding: .utf8), "tampered")
    }

    func testZshShimSyntaxChecks() throws {
        let installed = try ShellIntegration.install(into: root, version: "0.1.0")
        for name in [".zshenv", ".zprofile", ".zshrc", "ante-integration.zsh"] {
            let file = installed.zshDirectory.appendingPathComponent(name)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-n", file.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "zsh -n failed for \(name)")
        }
    }

    /// Runs a real interactive zsh through the shim and reports the variables that matter.
    private func zshUnderShim(userZdotdir: URL?) throws -> [String: String] {
        let installed = try ShellIntegration.install(into: root, version: "0.1.0")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let userZdotdir {
            try FileManager.default.createDirectory(at: userZdotdir, withIntermediateDirectories: true)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-il", "-c", "print -r -- \"HISTFILE=$HISTFILE\"; print -r -- \"ZDOTDIR=$ZDOTDIR\"; print -r -- \"LOADED=$ANTE_INTEGRATION_LOADED\""]
        var env = ["HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color",
                   "ZDOTDIR": installed.zshDirectory.path, "ANTE_SHELL_INTEGRATION": "1"]
        if let userZdotdir { env["ANTE_USER_ZDOTDIR"] = userZdotdir.path }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            out[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return out
    }

    func testRealZshRestoresZdotdirAndKeepsHistoryOutOfTheShim() throws {
        let vars = try zshUnderShim(userZdotdir: nil)
        XCTAssertEqual(vars["LOADED"], "1", "integration did not load: \(vars)")
        XCTAssertEqual(vars["ZDOTDIR"], "", "ZDOTDIR must be unset again after startup")
        // /etc/zshrc set HISTFILE while ZDOTDIR pointed at the shim; the shim must move it home.
        XCTAssertEqual(vars["HISTFILE"], root.appendingPathComponent("home/.zsh_history").path)
    }

    func testRealZshHonoursUsersOwnZdotdir() throws {
        let userDir = root.appendingPathComponent("user-zdotdir")
        let vars = try zshUnderShim(userZdotdir: userDir)
        XCTAssertEqual(vars["LOADED"], "1", "\(vars)")
        XCTAssertEqual(vars["ZDOTDIR"], userDir.path)
        XCTAssertEqual(vars["HISTFILE"], userDir.appendingPathComponent(".zsh_history").path)
    }

    func testBashShimSyntaxChecks() throws {
        let installed = try ShellIntegration.install(into: root, version: "0.1.0")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", installed.bashInitFile.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
