// Packages/AnteCore/Sources/AnteCore/Accounts/LiveConversation.swift
import Darwin
import Foundation

/// The conversation a running agent has open right now, and whether it is mid-reply.
public struct LiveConversation: Equatable, Sendable {
    public let id: String
    public let isBusy: Bool

    public init(id: String, isBusy: Bool) {
        self.id = id
        self.isBusy = isBusy
    }
}

/// Reads which conversation a running agent process has open, from the agent's own state rather
/// than its command line (which goes stale after `/clear` or `/resume`).
public enum LiveConversationReader {
    /// Claude Code keeps `<config>/sessions/<pid>.json` for each running interactive session, with
    /// its current `sessionId` and `status` (`busy` while replying). It follows `/clear`.
    public static func claude(pid: Int32, configDirectory: URL) -> LiveConversation? {
        let file = configDirectory.appendingPathComponent("sessions/\(pid).json")
        guard let data = try? Data(contentsOf: file),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = object["sessionId"] as? String,
              AgentKind.claude.resumeCommand(sessionID: id) != nil else { return nil }   // a safe token only
        return LiveConversation(id: id, isBusy: (object["status"] as? String) == "busy")
    }

    /// Codex appends to `sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` while a conversation
    /// is open; the uuid is the id `codex resume` takes.
    public static func codexID(openFiles: [String]) -> String? {
        let pattern = try! NSRegularExpression(pattern: "/sessions/.*/rollout-.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\\.jsonl$")
        for path in openFiles {
            let range = NSRange(path.startIndex..., in: path)
            if let match = pattern.firstMatch(in: path, range: range), let id = Range(match.range(at: 1), in: path) {
                return String(path[id])
            }
        }
        return nil
    }

    /// Paths of the regular files a process has open (libproc; same-user processes only).
    public static func openFiles(pid: Int32) -> [String] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 16)
        let filled = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for fd in fds.prefix(Int(filled) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { continue }
            let path = withUnsafeBytes(of: &info.pvip.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !path.isEmpty { paths.append(path) }
        }
        return paths
    }
}

/// Which account a running agent is, from the variables in its environment.
public enum AccountResolver {
    /// No variable: the default-folder account. A variable: the account whose folder it names.
    /// Nil when the folder isn't one Ante knows (the person chose a folder themselves).
    public static func account(for environment: [String: String], agent: AccountAgent, accounts: [AgentAccount],
                               paths: AccountPaths) -> AgentAccount? {
        let candidates = accounts.filter { $0.agent == agent }
        guard let value = environment[agent.configVariable], !value.isEmpty else {
            return candidates.first { $0.isDefaultFolder }
        }
        let wanted = URL(fileURLWithPath: value).standardizedFileURL.path
        return candidates.first { $0.folder(in: paths).standardizedFileURL.path == wanted }
    }
}
