// Packages/AnteTerm/Sources/AnteTerm/Session/ForegroundProbe.swift
import Darwin
import Foundation

/// Who is in the foreground of a pty, and what its command line is.
public struct ForegroundInfo: Equatable, Sendable {
    public let pid: pid_t
    public let commandLine: [String]
    /// The few variables Ante reads from the process: which account an agent runs as
    /// (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) and which pane it was started in (`ANTE_PANE_ID`).
    public var environment: [String: String] = [:]
    public var executableName: String { (commandLine.first as NSString?)?.lastPathComponent ?? "?" }

    public init(pid: pid_t, commandLine: [String], environment: [String: String] = [:]) {
        self.pid = pid
        self.commandLine = commandLine
        self.environment = environment
    }
}

public enum ForegroundProbe {
    /// The variables `ForegroundInfo.environment` keeps.
    public static let environmentKeys: Set<String> = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "ANTE_PANE_ID"]

    /// The foreground process group leader of the pty behind `fd`.
    public static func foreground(ptyFD fd: Int32) -> ForegroundInfo? {
        let pgid = tcgetpgrp(fd)
        guard pgid > 0 else { return nil }
        let args = processArguments(pid: pgid)
        return ForegroundInfo(pid: pgid, commandLine: args.argv, environment: pick(args.env, keys: environmentKeys))
    }

    /// argv of a process via `KERN_PROCARGS2`. Empty when unavailable (zombie, permissions).
    public static func commandLine(pid: pid_t) -> [String] { processArguments(pid: pid).argv }

    /// The values of `keys` in a process's environment (same user only; empty when unreadable).
    public static func environment(pid: pid_t, keys: Set<String>) -> [String: String] {
        pick(processArguments(pid: pid).env, keys: keys)
    }

    private static func pick(_ env: [String], keys: Set<String>) -> [String: String] {
        var out: [String: String] = [:]
        for entry in env {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<eq])
            if keys.contains(key), out[key] == nil { out[key] = String(entry[entry.index(after: eq)...]) }
        }
        return out
    }

    /// `KERN_PROCARGS2`: argc, the exec path, NUL padding, argv[0..argc), then the environment.
    private static func processArguments(pid: pid_t) -> (argv: [String], env: [String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return ([], []) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ([], []) }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var argv: [String] = []
        var env: [String] = []
        var current: [UInt8] = []
        while index < size {
            if buffer[index] == 0 {
                if argv.count < argc {
                    argv.append(String(decoding: current, as: UTF8.self))
                } else if current.isEmpty {
                    break   // the environment ends at the first empty string
                } else {
                    env.append(String(decoding: current, as: UTF8.self))
                }
                current.removeAll()
            } else {
                current.append(buffer[index])
            }
            index += 1
        }
        if !current.isEmpty, argv.count < argc { argv.append(String(decoding: current, as: UTF8.self)) }
        return (argv, env)
    }
}
