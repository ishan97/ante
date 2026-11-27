// Packages/AnteCore/Sources/AnteCore/Accounts/AccountLaunch.swift
import Foundation

/// How Ante starts an agent as a given account. Every command it types must do the right thing
/// with or without the launcher on PATH: a folder account sets the agent's variable explicitly,
/// and the default-folder account says `ANTE_ACCOUNT=default`, which the launcher reads as "don't
/// ask" and an unwrapped agent simply ignores.
public enum AccountLaunch {
    /// The variable assignment to put before the agent's command, with a trailing space; empty
    /// without an account. Paths are absolute (fish does not expand `~` in `VAR=value cmd`).
    public static func prefix(for account: AgentAccount?, paths: AccountPaths) -> String {
        guard let account else { return "" }
        if account.isDefaultFolder { return "ANTE_ACCOUNT=default " }
        return "\(account.agent.configVariable)=\(ShellQuote.quote(account.folder(in: paths).path)) "
    }

    public static func command(_ base: String, account: AgentAccount?, paths: AccountPaths) -> String {
        prefix(for: account, paths: paths) + base
    }

    /// The environment a process needs to run as `account`.
    public static func environment(for account: AgentAccount, paths: AccountPaths) -> (set: [String: String], unset: [String]) {
        account.isDefaultFolder
            ? ([:], [account.agent.configVariable])
            : ([account.agent.configVariable: account.folder(in: paths).path], [])
    }
}
