import Foundation
import Darwin

/// Finds the shell to launch: the account's login shell, then `$SHELL`, then zsh.
public enum LoginShell {
    public static func resolve(environment: [String: String]) -> String {
        resolve(environment: environment, passwordEntryShell: passwordEntryShell())
    }

    static func resolve(environment: [String: String], passwordEntryShell: String?) -> String {
        if let shell = passwordEntryShell, !shell.isEmpty { return shell }
        if let shell = environment["SHELL"], !shell.isEmpty { return shell }
        return "/bin/zsh"
    }

    private static func passwordEntryShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }
}
