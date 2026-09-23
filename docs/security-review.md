# Security review

Date: 2026-09-09, kept current since. Reviewer: the authors, checking each requirement below with
a command or a test rather than by reading.

| Requirement | Evidence | Status |
|---|---|---|
| Network access limited to the updater | `git grep -nE "URLSession\|NWConnection\|CFStream\|NSURLConnection\|socket\("` over `Packages` and `Ante` → no matches; the only network client is Sparkle (`Ante/Updater.swift`), which fetches `appcast.xml` once a day (off via Settings → General → Updates) and downloads a release DMG only after the user clicks Install. Sparkle verifies the EdDSA signature (`SUPublicEDKey`) and Apple's code signature before installing. | pass |
| Hardened Runtime, minimal entitlements | Debug build is ad-hoc signed with only `com.apple.security.get-task-allow` (Xcode adds it for debugging; Release drops it). `scripts/package.sh` signs with `--options runtime`; `codesign -d --entitlements -` on the packaged app shows an empty dictionary. Notarization requires a Developer ID certificate, not required for a local build — documented in the script. | pass (Release) |
| Shell integration never edits user files | `git grep` for rc-file names in `Packages/AnteTerm/Sources` finds only the shim's own file-name table. The shim *sources* the user's files with `ZDOTDIR` temporarily restored. `ShellIntegrationTests.testRealZshRestoresZdotdirAndKeepsHistoryOutOfTheShim` and `testRealZshHonoursUsersOwnZdotdir` run a real zsh and assert `ZDOTDIR` is handed back and `HISTFILE` lands in the user's directory. | pass |
| Paste | No confirmation dialog (removed in 1.3: it got in the way of answering agents). Bracketed paste is SwiftTerm's default, so a shell that supports it receives a multi-line paste as one block rather than line by line. | pass |
| Clickable URLs: `http`, `https`, `mailto`, `file` only | `LinkDetector.allowedSchemes`; `LinkDetectorTests.testRejectsDisallowedSchemes`; `LinkOpener.plan` re-checks the scheme. Paths and `file:` URLs open in the text editor (files) or Finder (directories) — never `NSWorkspace.open`, which would execute scripts and binaries. `BugReviewTests.testLinkOpenerNeverExecutes`. | pass (fixed during review) |
| Config is data, not code | TOML only. `ConfigEditor` writes scalars and string arrays. The only process launched from a config value is the user's chosen shell (`[shell] program`). | pass |
| Screen contents never touch disk | Scrollback persistence was removed before 1.0: on quit a session's name, folder and last command go to History (`AtomicFile`, `0600`); nothing else is written. Any pre-existing scrollback directory is deleted at launch. `WorkspaceRuntimeTests.testQuitMovesSessionsToHistoryAndLaunchStartsFresh`. | pass |
| Hotkey window does not float over login / secure input | The summoned window uses `HotkeyWindowToggler.summonedLevel` (below the menu bar) and never sets `canBecomeVisibleWithoutLogin`. | pass |
| Dependencies pinned to exact versions | `git grep -n "exact:" Packages/*/Package.swift`: SwiftTerm 1.20.0, TOMLKit 0.6.0, KeyboardShortcuts 3.0.1, each pinned in every manifest that uses it. | pass |
| Agent hooks | Ante installs only `cat >> "<event file under App Support>"` for `Notification`/`Stop`/`UserPromptSubmit`, opt-in, after backing up `settings.json` (five backups kept); uninstall removes only groups containing that path and deletes the event log (`HookTests`). Ante reads the event file (never executes anything from it), and empties it once read past 256 KB so prompts are not kept. | pass |
| Resume commands | Built only from `AgentKind.resumeCommand(sessionID:)` templates with the id validated against `[A-Za-z0-9._-]{8,80}` (`AgentsTests.testResumeCommandsAreTemplatedAndValidated`); never from free text in a session file. History scanners read at most 64 KB per file and display only the title line. | pass |

## Findings

1. **⌘-click executed paths** (fixed). `WorkspaceRuntime.openLink` used `NSWorkspace.shared.open(URL(fileURLWithPath:))`, which launches executables. Replaced by `LinkOpener` (editor for files, Finder for directories), with a test.
2. **`[shell] integration = false` was ignored** (fixed). The launch factory always injected the shim. It now passes `nil` integration when the setting is off.
3. **Deferred: notarization.** Needs a Developer ID Application certificate; the packaging script documents the `notarytool` step.
4. **Deferred: `file:` URL hosts.** `file://host/path` is treated as a local path; a non-local host is ignored rather than resolved (there is no network path to resolve it over). Acceptable.

## Threat notes

- A hostile program running inside the terminal can emit any escape sequence. Ante's own parser
  (`OSCScanner`) is bounded (64 KB payload cap, aborts on C0 controls) and only interprets OSC 133
  and OSC 7; everything else is left to SwiftTerm. OSC 7 paths are only used for display and for
  the next spawn's cwd, never opened or executed.
- Titles (OSC 0/2), notifications (OSC 9) and hook messages come from programs in the terminal.
  They are stripped of control characters and capped (80 / 200 characters) before they reach a
  label, and only ever displayed — never executed or written anywhere but Ante's own state.
