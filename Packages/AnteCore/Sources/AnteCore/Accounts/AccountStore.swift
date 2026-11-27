// Packages/AnteCore/Sources/AnteCore/Accounts/AccountStore.swift
import Foundation

/// Reads and writes the account list and each agent's default choice.
///
/// The list is a tab-separated file because the launcher script (zsh) reads it too:
/// `agent  id  folder  name  email  org  plan`, one account per line, `#` lines ignored.
/// `folder` is empty for the default-folder account. The default choice is a one-line file per
/// agent holding an account id; no file means "ask every time".
public struct AccountStore: Sendable {
    public let paths: AccountPaths

    public init(paths: AccountPaths) {
        self.paths = paths
    }

    public static let header = "# agent\tid\tfolder\tname\temail\torg\tplan"

    public func load() -> [AgentAccount] {
        guard let text = try? String(contentsOf: paths.accountsFile, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line -> AgentAccount? in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let agent = AccountAgent(rawValue: fields[0]) else { return nil }
            let isDefaultFolder = fields[2].isEmpty
            let id = isDefaultFolder ? AgentAccount.defaultFolderID : fields[1]
            guard isDefaultFolder || Self.isValidID(id), seen.insert("\(agent.rawValue)/\(id)").inserted else { return nil }
            func field(_ i: Int) -> String? { i < fields.count && !fields[i].isEmpty ? fields[i] : nil }
            return AgentAccount(id: id, agent: agent, name: fields[3].isEmpty ? (field(4) ?? agent.displayName) : fields[3],
                                email: field(4), org: field(5), plan: field(6), isDefaultFolder: isDefaultFolder)
        }
    }

    public func save(_ accounts: [AgentAccount]) throws {
        var lines = [Self.header]
        for account in accounts {
            let folder = account.isDefaultFolder ? "" : account.folder(in: paths).path
            let fields = [account.agent.rawValue, account.id, folder, account.name,
                          account.email ?? "", account.org ?? "", account.plan ?? ""]
            lines.append(fields.map(Self.flatten).joined(separator: "\t"))
        }
        try AtomicFile.write(Data((lines.joined(separator: "\n") + "\n").utf8), to: paths.accountsFile)
    }

    public func defaultAccountID(for agent: AccountAgent) -> String? {
        guard let text = try? String(contentsOf: paths.defaultFile(for: agent), encoding: .utf8) else { return nil }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    public func setDefault(_ id: String?, for agent: AccountAgent) throws {
        let file = paths.defaultFile(for: agent)
        if let id {
            try AtomicFile.write(Data((id + "\n").utf8), to: file)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// 8 lowercase alphanumerics: short enough to read in a typed command, and never "default".
    public static func newID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in alphabet[Int(generator.next(upperBound: UInt(alphabet.count)))] })
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 32 && id != AgentAccount.defaultFolderID
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    private static func flatten(_ field: String) -> String {
        field.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
