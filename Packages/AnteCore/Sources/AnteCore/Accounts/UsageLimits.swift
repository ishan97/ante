import Foundation
import CryptoKit

/// One limit a provider enforces, as what is left of it: the 5-hour session, the week, or a
/// model with its own allowance ("Fable", or a Gemini quota pool).
public struct UsageWindow: Equatable, Sendable {
    /// "5h", "Wk", or a model family ("Fable", "Gemini").
    public let label: String
    /// 0…100, what is left (the providers report what is used; this is the other side).
    public let percentLeft: Int
    public let resetsAt: Date?

    public init(label: String, percentLeft: Int, resetsAt: Date?) {
        self.label = label
        self.percentLeft = min(max(percentLeft, 0), 100)
        self.resetsAt = resetsAt
    }
}

/// What an account's `/usage` screen would show, as far as Ante could tell.
public enum UsageLimits: Equatable, Sendable {
    case windows([UsageWindow])
    /// The saved sign-in token has run out; starting the agent on that account renews it.
    case tokenExpired
    /// No answer this time (offline, rate limited, signed out, or a shape Ante doesn't know).
    case unavailable
}

/// A sign-in token as the agent saved it, used to ask for the account's limits. Only an expired
/// Claude token is ever renewed (`ClaudeRenewal`); the others are read, never written.
public struct UsageToken: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    /// Codex's ChatGPT workspace, sent as `ChatGPT-Account-Id`.
    public let accountID: String?

    public init(accessToken: String, expiresAt: Date?, accountID: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }

    /// `margin` treats a token about to run out as already gone, as Claude Code does.
    public func isExpired(now: Date, margin: TimeInterval = 0) -> Bool { expiresAt.map { $0 <= now.addingTimeInterval(margin) } ?? false }
}

/// Reading saved tokens and the providers' answers. Every shape here was observed on real
/// accounts (2026-11); none of the endpoints is documented, so anything unexpected is nil.
public enum UsageLimitsParser {
    // MARK: - Tokens

    /// Claude Code keeps an account's sign-in in the Keychain item `Claude Code-credentials`,
    /// suffixed with the first 8 hex digits of SHA-256 of `CLAUDE_CONFIG_DIR` when that is set.
    public static func claudeKeychainService(configFolder: String?) -> String {
        guard let configFolder else { return "Claude Code-credentials" }
        let digest = SHA256.hash(data: Data(configFolder.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(digest.prefix(8))"
    }

    /// `{"claudeAiOauth": {"accessToken": …, "expiresAt": <ms>}}`.
    public static func claudeToken(_ keychainValue: String) -> UsageToken? {
        guard let oauth = json(Data(keychainValue.utf8))?["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return UsageToken(accessToken: token, expiresAt: expires)
    }

    /// `<CODEX_HOME>/auth.json`: `tokens.access_token` (a JWT whose `exp` is its expiry) and
    /// `tokens.account_id`. An API-key sign-in has no tokens and no limits to show.
    public static func codexToken(_ authJSON: Data) -> UsageToken? {
        guard let tokens = json(authJSON)?["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else { return nil }
        let expires = jwtClaims(token).flatMap { number($0["exp"]) }.map { Date(timeIntervalSince1970: $0) }
        return UsageToken(accessToken: token, expiresAt: expires, accountID: tokens["account_id"] as? String)
    }

    /// agy's Keychain item (service `gemini`, account `antigravity`), written by go-keyring:
    /// `go-keyring-base64:` + base64 of `{"token": {"access_token": …, "expiry": <RFC 3339>}}`.
    public static func antigravityToken(_ keychainValue: String) -> UsageToken? {
        let trimmed = keychainValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "go-keyring-base64:"
        let payload: Data?
        if trimmed.hasPrefix(prefix) {
            var encoded = String(trimmed.dropFirst(prefix.count))
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            payload = Data(base64Encoded: encoded)
        } else {
            payload = Data(trimmed.utf8)
        }
        guard let payload, let token = json(payload)?["token"] as? [String: Any],
              let access = token["access_token"] as? String, !access.isEmpty else { return nil }
        return UsageToken(accessToken: access, expiresAt: date(token["expiry"]))
    }

    // MARK: - Limits

    /// Anthropic's `api/oauth/usage` (what Claude Code's `/usage` shows). Prefers its `limits`
    /// list (session, weekly, and per-model weekly with a display name); falls back to the
    /// older `five_hour` / `seven_day` objects. `percent` / `utilization` are what is used.
    public static func claudeLimits(_ data: Data) -> [UsageWindow]? {
        guard let object = json(data), object["error"] == nil else { return nil }
        if let limits = object["limits"] as? [[String: Any]], !limits.isEmpty {
            return limits.compactMap { item -> UsageWindow? in
                guard let used = number(item["percent"]) else { return nil }
                let label: String
                switch item["kind"] as? String {
                case "session": label = "5h"
                case "weekly_all": label = "Wk"
                default:
                    let scope = item["scope"] as? [String: Any]
                    guard let model = (scope?["model"] as? [String: Any])?["display_name"] as? String, !model.isEmpty else { return nil }
                    label = model
                }
                return UsageWindow(label: label, percentLeft: 100 - Int(used.rounded()), resetsAt: date(item["resets_at"]))
            }
        }
        let known = [("five_hour", "5h"), ("seven_day", "Wk"), ("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")]
        guard known.contains(where: { object.keys.contains($0.0) }) else { return nil }
        return known.compactMap { key, label in
            guard let window = object[key] as? [String: Any], let used = number(window["utilization"]) else { return nil }
            return UsageWindow(label: label, percentLeft: 100 - Int(used.rounded()), resetsAt: date(window["resets_at"]))
        }
    }

    /// ChatGPT's `backend-api/wham/usage` (what Codex's `/status` shows): up to two windows,
    /// named by their length, since a plan may have only the weekly one.
    public static func codexLimits(_ data: Data) -> [UsageWindow]? {
        guard let limit = json(data)?["rate_limit"] as? [String: Any] else { return nil }
        let windows = ["primary_window", "secondary_window"].compactMap { key -> (seconds: Double, window: UsageWindow)? in
            guard let window = limit[key] as? [String: Any], let used = number(window["used_percent"]) else { return nil }
            let seconds = number(window["limit_window_seconds"]) ?? 0
            let reset = number(window["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            return (seconds, UsageWindow(label: windowLabel(seconds: seconds), percentLeft: 100 - Int(used.rounded()), resetsAt: reset))
        }
        return windows.sorted { $0.seconds < $1.seconds }.map(\.window)
    }

    /// Google's `v1internal:fetchAvailableModels` as agy calls it: a fraction left per model.
    /// Models share a few quota pools, so models with the same fraction and reset are one pool,
    /// named after the family most of its models belong to ("Gemini", "Claude"). Models with no
    /// display name (completion helpers) are left out.
    public static func antigravityLimits(_ data: Data) -> [UsageWindow]? {
        guard let models = json(data)?["models"] as? [String: Any] else { return nil }
        var pools: [String: (fraction: Double, reset: Date?, families: [String: Int])] = [:]
        for case let model as [String: Any] in models.values {
            guard let name = model["displayName"] as? String, let family = name.split(separator: " ").first.map(String.init),
                  let quota = model["quotaInfo"] as? [String: Any] else { continue }
            let resetText = quota["resetTime"] as? String
            // Proto JSON leaves zero out: a pool with a reset but no fraction is used up.
            guard let fraction = number(quota["remainingFraction"]) ?? (resetText != nil ? 0 : nil) else { continue }
            let key = "\(fraction)|\(resetText ?? "")"
            var pool = pools[key] ?? (fraction, date(resetText), [:])
            pool.families[family, default: 0] += 1
            pools[key] = pool
        }
        // One entry per family: when two pools are named alike, the tighter one is what limits.
        var byLabel: [String: UsageWindow] = [:]
        for pool in pools.values {
            guard let label = pool.families.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { continue }
            let window = UsageWindow(label: label, percentLeft: Int((pool.fraction * 100).rounded(.down)), resetsAt: pool.reset)
            if let existing = byLabel[label], existing.percentLeft <= window.percentLeft { continue }
            byLabel[label] = window
        }
        return byLabel.values.sorted { ($0.label == "Gemini" ? 0 : 1, $0.label) < ($1.label == "Gemini" ? 0 : 1, $1.label) }
    }

    static func windowLabel(seconds: Double) -> String {
        let hours = Int((seconds / 3600).rounded())
        if hours <= 0 { return "Limit" }
        if hours == 24 * 7 { return "Wk" }
        if hours % 24 == 0 { return "\(hours / 24)d" }
        return "\(hours)h"
    }

    // MARK: - Helpers

    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where !(number === kCFBooleanTrue || number === kCFBooleanFalse): return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    /// RFC 3339 with any number of fractional digits (Anthropic sends six, Go nine), which
    /// `ISO8601DateFormatter` won't take, so the fraction is dropped first.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        return Data(base64Encoded: payload).flatMap(json)
    }
}

/// The one-line form under an account in a menu: "5h 56% → 3:30pm · Wk 79% · Fable 85% → Sat 7:30pm".
public enum UsageLimitsFormat {
    public static let expiredLine = "Token expired — start a session on this account to renew it"

    /// Nil when there is nothing worth a line (not fetched yet, or no answer).
    public static func line(_ limits: UsageLimits?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        switch limits {
        case let .windows(windows) where !windows.isEmpty: return line(windows, now: now, calendar: calendar)
        case .tokenExpired: return expiredLine
        default: return nil
        }
    }

    /// Percentages are what is left. A window that is untouched (100%) has nothing to wait for,
    /// so no reset; windows that reset at the same minute share one, written after the last.
    public static func line(_ windows: [UsageWindow], now: Date = Date(), calendar: Calendar = .current) -> String {
        func shownReset(_ window: UsageWindow) -> Date? { window.percentLeft < 100 ? window.resetsAt : nil }
        func sameMinute(_ a: Date?, _ b: Date?) -> Bool {
            guard let a, let b else { return false }
            return nearestMinute(a) == nearestMinute(b)
        }
        return windows.enumerated().map { index, window in
            var text = "\(window.label) \(window.percentLeft)%"
            if let reset = shownReset(window) {
                let next = index + 1 < windows.count ? shownReset(windows[index + 1]) : nil
                if !sameMinute(reset, next) { text += " → \(when(reset, now: now, calendar: calendar))" }
            }
            return text
        }.joined(separator: " · ")
    }

    /// Resets come a few milliseconds either side of the minute (03:59:59.98); show the minute.
    static func nearestMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    /// "3:30pm" today, "Sat 7:30pm" within the week, "4 Dec" after that.
    public static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let date = nearestMinute(date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        if date <= now { return "now" }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: formatter.dateFormat = "h:mma"
        case 1...6: formatter.dateFormat = "EEE h:mma"
        default: formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }
}

/// Renewing a Claude sign-in the way Claude Code does, for an account whose access token has
/// run out while no Claude was using it. Only the request and the credential edit live here;
/// the lock and the Keychain are the caller's.
public enum ClaudeRenewal {
    /// Claude Code's OAuth client and token endpoint (`claude` 2.1.x).
    public static let defaultClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// The lock Claude Code takes inside the config folder before it renews.
    public static let lockName = ".oauth_refresh.lock"
    /// Renew this long before expiry, so a check never lands on a token in its last seconds.
    public static let margin: TimeInterval = 300
    /// The longest command `security -i` takes on stdin (Claude Code's own limit); a longer
    /// write goes on the command line instead, as Claude Code does.
    public static let stdinCommandLimit = 4032
    /// The keys of a credential item in the plain, one-item shape. Anything else (an item Claude
    /// Code split across several Keychain entries, or a newer format) is left alone.
    static let plainKeys: Set<String> = ["claudeAiOauth", "mcpOAuth"]

    /// Whether Ante may renew this item: the plain shape, with all three token fields present.
    public static func isPlainItem(credentials: String) -> Bool {
        guard let root = UsageLimitsParser.json(Data(credentials.utf8)), Set(root.keys).isSubset(of: plainKeys),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              (oauth["accessToken"] as? String)?.isEmpty == false, (oauth["refreshToken"] as? String)?.isEmpty == false,
              UsageLimitsParser.number(oauth["expiresAt"]) != nil else { return false }
        return true
    }

    /// Whether the account and service names can go inside `security -i`'s double quotes.
    public static func isQuotable(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { $0 == "\"" || $0 == "\\" || $0.isNewline })
    }

    /// The hex form Claude Code stores (`-X`).
    public static func hex(_ value: String) -> String { Data(value.utf8).map { String(format: "%02x", $0) }.joined() }

    /// The `security -i` line Claude Code writes the item with; nil when a name can't be quoted
    /// or the line is longer than `security -i` reads.
    public static func stdinCommand(account: String, service: String, value: String) -> String? {
        guard isQuotable(account), isQuotable(service) else { return nil }
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex(value))\" "
        return command.count <= stdinCommandLimit ? command : nil
    }

    /// The JSON body Claude Code posts, from the saved credentials; nil when there is no
    /// refresh token to send.
    public static func requestBody(credentials: String) -> Data? {
        guard let oauth = UsageLimitsParser.json(Data(credentials.utf8))?["claudeAiOauth"] as? [String: Any],
              let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty else { return nil }
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refresh,
                                   "client_id": oauth["clientId"] as? String ?? defaultClientID]
        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The refresh token in the saved credentials.
    public static func refreshToken(credentials: String) -> String? {
        (UsageLimitsParser.json(Data(credentials.utf8))?["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    /// The saved credentials with the renewed tokens in place: only `accessToken`,
    /// `refreshToken` and `expiresAt` change; everything else (MCP sign-ins, scopes, plan) is
    /// kept. Nil when the reply has no access token or the credentials don't parse.
    public static func renewed(credentials: String, reply: Data, now: Date) -> String? {
        guard var root = UsageLimitsParser.json(Data(credentials.utf8)),
              var oauth = root["claudeAiOauth"] as? [String: Any],
              let answer = UsageLimitsParser.json(reply),
              let access = answer["access_token"] as? String, !access.isEmpty,
              let lifetime = UsageLimitsParser.number(answer["expires_in"]), lifetime > 0 else { return nil }
        oauth["accessToken"] = access
        if let refresh = answer["refresh_token"] as? String, !refresh.isEmpty { oauth["refreshToken"] = refresh }
        oauth["expiresAt"] = Int64((now.timeIntervalSince1970 + lifetime) * 1000)
        root["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
