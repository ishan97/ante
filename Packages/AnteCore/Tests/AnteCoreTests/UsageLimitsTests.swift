import XCTest
@testable import AnteCore

final class UsageLimitsTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Tokens

    func testClaudeKeychainServiceIsSuffixedWithTheFolderHash() {
        XCTAssertEqual(UsageLimitsParser.claudeKeychainService(configFolder: nil), "Claude Code-credentials")
        let service = UsageLimitsParser.claudeKeychainService(configFolder: "/tmp/x")
        XCTAssertTrue(service.hasPrefix("Claude Code-credentials-"))
        XCTAssertEqual(service.count, "Claude Code-credentials-".count + 8)
        XCTAssertNotEqual(service, UsageLimitsParser.claudeKeychainService(configFolder: "/tmp/y"))
    }

    func testClaudeTokenReadsAccessTokenAndMillisecondExpiry() {
        let token = UsageLimitsParser.claudeToken(#"{"claudeAiOauth":{"accessToken":"abc","refreshToken":"r","expiresAt":1764320000000}}"#)
        XCTAssertEqual(token?.accessToken, "abc")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_764_320_000))
        XCTAssertNil(UsageLimitsParser.claudeToken("{}"))
        XCTAssertNil(UsageLimitsParser.claudeToken("not json"))
    }

    func testCodexTokenReadsJWTExpiryAndAccount() {
        let claims = Data(#"{"exp":1796000000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let auth = #"{"auth_mode":"chatgpt","tokens":{"access_token":"h.\#(claims).s","account_id":"acct-1","id_token":"x"}}"#
        let token = UsageLimitsParser.codexToken(data(auth))
        XCTAssertEqual(token?.accountID, "acct-1")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_796_000_000))
        XCTAssertNil(UsageLimitsParser.codexToken(data(#"{"OPENAI_API_KEY":"sk-1","tokens":null}"#)))
    }

    func testAntigravityTokenDecodesGoKeyringBase64() {
        let inner = #"{"token":{"access_token":"ya29","expiry":"2026-11-28T14:36:56.541895+05:30","refresh_token":"r"},"auth_method":"consumer"}"#
        let token = UsageLimitsParser.antigravityToken("go-keyring-base64:" + Data(inner.utf8).base64EncodedString())
        XCTAssertEqual(token?.accessToken, "ya29")
        XCTAssertEqual(token?.expiresAt, date("2026-11-28T09:06:56Z"))
        XCTAssertEqual(token?.isExpired(now: date("2026-11-28T09:00:00Z")), false)
        XCTAssertEqual(token?.isExpired(now: date("2026-11-28T10:00:00Z")), true)
    }

    // MARK: - Claude

    func testClaudeLimitsListBecomesWhatIsLeft() {
        let response = #"""
        {"five_hour":{"utilization":0.0,"resets_at":"2026-11-28T10:30:00.072601+00:00"},
         "limits":[
          {"kind":"session","group":"session","percent":44,"severity":"normal","resets_at":"2026-11-28T10:30:00.072601+00:00","scope":null,"is_active":false},
          {"kind":"weekly_all","group":"weekly","percent":21,"severity":"warning","resets_at":"2026-11-29T04:00:00.072622+00:00","scope":null},
          {"kind":"weekly_scoped","group":"weekly","percent":100,"severity":"critical","resets_at":"2026-11-29T04:00:00.017507+00:00",
           "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}},
          {"kind":"something_new","group":"weekly","percent":3,"scope":null}
         ]}
        """#
        XCTAssertEqual(UsageLimitsParser.claudeLimits(data(response)), [
            UsageWindow(label: "5h", percentLeft: 56, resetsAt: date("2026-11-28T10:30:00Z")),
            UsageWindow(label: "Wk", percentLeft: 79, resetsAt: date("2026-11-29T04:00:00Z")),
            UsageWindow(label: "Fable", percentLeft: 0, resetsAt: date("2026-11-29T04:00:00Z")),
        ])
    }

    func testClaudeFallsBackToTheOlderObjects() {
        let response = #"{"five_hour":null,"seven_day":{"utilization":5.0,"resets_at":"2026-12-04T19:00:00.397380+00:00"}}"#
        XCTAssertEqual(UsageLimitsParser.claudeLimits(data(response)), [
            UsageWindow(label: "Wk", percentLeft: 95, resetsAt: date("2026-12-04T19:00:00Z")),
        ])
    }

    func testClaudeErrorsAreNotLimits() {
        XCTAssertNil(UsageLimitsParser.claudeLimits(data(#"{"error":{"type":"rate_limit_error","message":"Rate limited."}}"#)))
        XCTAssertNil(UsageLimitsParser.claudeLimits(data(#"{"type":"error","error":{"type":"authentication_error"}}"#)))
        XCTAssertNil(UsageLimitsParser.claudeLimits(data("<html>")))
    }

    // MARK: - Codex

    func testCodexWindowsAreNamedByLengthAndOrderedShortestFirst() {
        let response = #"""
        {"plan_type":"plus","rate_limit":{"allowed":true,
          "primary_window":{"used_percent":21,"limit_window_seconds":604800,"reset_at":1796000000},
          "secondary_window":{"used_percent":9,"limit_window_seconds":18000,"reset_at":1795900000}}}
        """#
        XCTAssertEqual(UsageLimitsParser.codexLimits(data(response)), [
            UsageWindow(label: "5h", percentLeft: 91, resetsAt: Date(timeIntervalSince1970: 1_795_900_000)),
            UsageWindow(label: "Wk", percentLeft: 79, resetsAt: Date(timeIntervalSince1970: 1_796_000_000)),
        ])
    }

    func testCodexWeeklyOnlyPlan() {
        let response = #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1796000000},"secondary_window":null}}"#
        XCTAssertEqual(UsageLimitsParser.codexLimits(data(response))?.map(\.label), ["Wk"])
        XCTAssertNil(UsageLimitsParser.codexLimits(data(#"{"detail":"Unauthorized"}"#)))
    }

    // MARK: - Antigravity

    func testAntigravityModelsCollapseIntoNamedPools() {
        let response = #"""
        {"models":{
          "gemini-3-flash":{"displayName":"Gemini 3 Flash","quotaInfo":{"remainingFraction":0.9898427,"resetTime":"2026-11-28T13:07:29Z"}},
          "gemini-3.1-flash-lite":{"displayName":"Gemini 3.1 Flash Lite","quotaInfo":{"remainingFraction":0.9898427,"resetTime":"2026-11-28T13:07:29Z"}},
          "claude-opus-high":{"displayName":"Claude Opus 5.5 (High)","quotaInfo":{"remainingFraction":0.5,"resetTime":"2026-11-28T13:24:38Z"}},
          "claude-sonnet-low":{"displayName":"Claude Sonnet 5.5 (Low)","quotaInfo":{"remainingFraction":0.5,"resetTime":"2026-11-28T13:24:38Z"}},
          "gpt-oss":{"displayName":"GPT-OSS 120B (Medium)","quotaInfo":{"remainingFraction":0.5,"resetTime":"2026-11-28T13:24:38Z"}},
          "tab_flash_lite_preview":{"quotaInfo":{"remainingFraction":1}},
          "gemini-pro":{"displayName":"Gemini 3 Pro","quotaInfo":{"resetTime":"2026-11-28T15:00:00Z"}}
        }}
        """#
        XCTAssertEqual(UsageLimitsParser.antigravityLimits(data(response)), [
            UsageWindow(label: "Gemini", percentLeft: 0, resetsAt: date("2026-11-28T15:00:00Z")),
            UsageWindow(label: "Claude", percentLeft: 50, resetsAt: date("2026-11-28T13:24:38Z")),
        ])
        XCTAssertNil(UsageLimitsParser.antigravityLimits(data(#"{"error":{"code":403}}"#)))
    }

    // MARK: - Format

    func testLineSharesAResetAndSkipsUntouchedWindows() {
        let now = date("2026-11-28T08:00:00Z")   // a Saturday
        let windows = [
            UsageWindow(label: "5h", percentLeft: 56, resetsAt: date("2026-11-28T15:30:00Z")),
            UsageWindow(label: "Wk", percentLeft: 79, resetsAt: date("2026-12-03T19:30:00Z")),
            UsageWindow(label: "Fable", percentLeft: 85, resetsAt: date("2026-12-03T19:30:00Z")),
        ]
        XCTAssertEqual(UsageLimitsFormat.line(windows, now: now, calendar: utc), "5h 56% → 3:30pm · Wk 79% · Fable 85% → Thu 7:30pm")

        let fresh = [
            UsageWindow(label: "5h", percentLeft: 100, resetsAt: date("2026-11-28T15:30:00Z")),
            UsageWindow(label: "Wk", percentLeft: 64, resetsAt: date("2026-12-20T09:00:00Z")),
        ]
        XCTAssertEqual(UsageLimitsFormat.line(fresh, now: now, calendar: utc), "5h 100% · Wk 64% → 20 Dec")
    }

    func testLineForExpiredAndUnknown() {
        XCTAssertEqual(UsageLimitsFormat.line(.tokenExpired), UsageLimitsFormat.expiredLine)
        XCTAssertNil(UsageLimitsFormat.line(.unavailable))
        XCTAssertNil(UsageLimitsFormat.line(nil))
        XCTAssertNil(UsageLimitsFormat.line(.windows([])))
    }

    func testWhen() {
        let now = date("2026-11-28T08:00:00Z")
        XCTAssertEqual(UsageLimitsFormat.when(date("2026-11-28T21:05:00Z"), now: now, calendar: utc), "9:05pm")
        XCTAssertEqual(UsageLimitsFormat.when(date("2026-11-29T09:00:00Z"), now: now, calendar: utc), "Sun 9:00am")
        XCTAssertEqual(UsageLimitsFormat.when(date("2026-11-28T07:00:00Z"), now: now, calendar: utc), "now")
        XCTAssertEqual(UsageLimitsFormat.when(date("2026-11-29T08:59:59Z").addingTimeInterval(0.98), now: now, calendar: utc), "Sun 9:00am")
    }
}

final class ClaudeRenewalTests: XCTestCase {
    private let saved = #"{"claudeAiOauth":{"accessToken":"old-a","refreshToken":"old-r","expiresAt":1764320000000,"scopes":["user:inference","user:profile"],"subscriptionType":"team","rateLimitTier":"t"},"mcpOAuth":{"srv|1":{"accessToken":"m","expiresAt":12}}}"#

    func testRequestBodyMatchesClaudeCode() throws {
        let body = try XCTUnwrap(ClaudeRenewal.requestBody(credentials: saved))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["grant_type": "refresh_token", "refresh_token": "old-r",
                                "client_id": ClaudeRenewal.defaultClientID, "scope": "user:inference user:profile"])
        XCTAssertNil(ClaudeRenewal.requestBody(credentials: #"{"claudeAiOauth":{"accessToken":"a"}}"#))
    }

    func testRenewedReplacesOnlyTheTokens() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reply = Data(#"{"access_token":"new-a","refresh_token":"new-r","expires_in":28800,"token_type":"Bearer"}"#.utf8)
        let text = try XCTUnwrap(ClaudeRenewal.renewed(credentials: saved, reply: reply, now: now))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let oauth = try XCTUnwrap(root["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "new-a")
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-r")
        XCTAssertEqual((oauth["expiresAt"] as? NSNumber)?.int64Value, 1_800_028_800_000)
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:inference", "user:profile"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "team")
        XCTAssertEqual(((root["mcpOAuth"] as? [String: Any])?["srv|1"] as? [String: Any])?["accessToken"] as? String, "m")
        XCTAssertEqual(UsageLimitsParser.claudeToken(text)?.accessToken, "new-a")
    }

    func testOnlyThePlainItemShapeIsRenewed() {
        XCTAssertTrue(ClaudeRenewal.isPlainItem(credentials: saved))
        XCTAssertTrue(ClaudeRenewal.isPlainItem(credentials: #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":1}}"#))
        XCTAssertFalse(ClaudeRenewal.isPlainItem(credentials: #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":1},"keychainOverflow":{"slot":"a"}}"#),
                       "an item split across Keychain entries is Claude Code's to write")
        XCTAssertFalse(ClaudeRenewal.isPlainItem(credentials: #"{"claudeAiOauth":{"accessToken":"a","expiresAt":1}}"#))
        XCTAssertFalse(ClaudeRenewal.isPlainItem(credentials: "garbage"))
    }

    func testStdinCommandMatchesClaudeCodeAndItsLimit() throws {
        let command = try XCTUnwrap(ClaudeRenewal.stdinCommand(account: "me", service: "Claude Code-credentials-1234abcd", value: "{}"))
        XCTAssertEqual(command, #"add-generic-password -U -a "me" -s "Claude Code-credentials-1234abcd" -X "7b7d" "#)
        XCTAssertNil(ClaudeRenewal.stdinCommand(account: "me", service: "s", value: String(repeating: "x", count: 2100)),
                     "over security -i's limit: the caller must not send a cut-off line")
        XCTAssertNil(ClaudeRenewal.stdinCommand(account: #"a"b"#, service: "s", value: "{}"))
        XCTAssertNil(ClaudeRenewal.stdinCommand(account: #"a\b"#, service: "s", value: "{}"))
        XCTAssertNil(ClaudeRenewal.stdinCommand(account: "a\nb", service: "s", value: "{}"))
    }

    func testExpiryMargin() {
        let token = UsageToken(accessToken: "a", expiresAt: Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(token.isExpired(now: Date(timeIntervalSince1970: 800)))
        XCTAssertTrue(token.isExpired(now: Date(timeIntervalSince1970: 800), margin: ClaudeRenewal.margin))
    }

    func testRenewedKeepsTheRefreshTokenWhenNoneComesBack() throws {
        let reply = Data(#"{"access_token":"new-a","expires_in":3600}"#.utf8)
        let text = try XCTUnwrap(ClaudeRenewal.renewed(credentials: saved, reply: reply, now: Date()))
        XCTAssertEqual(ClaudeRenewal.refreshToken(credentials: text), "old-r")
        XCTAssertNil(ClaudeRenewal.renewed(credentials: saved, reply: Data(#"{"error":"invalid_grant"}"#.utf8), now: Date()))
    }
}
