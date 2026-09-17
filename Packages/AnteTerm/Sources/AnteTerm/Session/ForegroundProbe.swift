// Packages/AnteTerm/Sources/AnteTerm/Session/ForegroundProbe.swift
import Darwin
import Foundation

/// Who is in the foreground of a pty, and what its command line is.
public struct ForegroundInfo: Equatable, Sendable {
    public let pid: pid_t
    public let commandLine: [String]
    public var executableName: String { (commandLine.first as NSString?)?.lastPathComponent ?? "?" }
}

public enum ForegroundProbe {
    /// The foreground process group leader of the pty behind `fd`.
    public static func foreground(ptyFD fd: Int32) -> ForegroundInfo? {
        let pgid = tcgetpgrp(fd)
        guard pgid > 0 else { return nil }
        return ForegroundInfo(pid: pgid, commandLine: commandLine(pid: pgid))
    }

    /// argv of a process via `KERN_PROCARGS2`. Empty when unavailable (zombie, permissions).
    public static func commandLine(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        // exec path, then NUL padding, then argv[0..argc)
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var args: [String] = []
        var current: [UInt8] = []
        while index < size, args.count < argc {
            if buffer[index] == 0 {
                args.append(String(decoding: current, as: UTF8.self)); current.removeAll()
            } else {
                current.append(buffer[index])
            }
            index += 1
        }
        if !current.isEmpty, args.count < argc { args.append(String(decoding: current, as: UTF8.self)) }
        return args
    }
}
