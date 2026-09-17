# Bug review — whole build, 2026-09-09

Method: read every file under `Packages/*/Sources` and `Ante/` with a fixed question list
(concurrency, lifetimes, process handling, persistence, UI state, config). Findings are ordered
by severity. Each fix carries a regression test unless the behaviour is view-only.

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | high | `WorkspaceRuntime.controller(for:)` spawned a *real shell* for any unknown pane ID and registered it. SwiftUI asks for a pane's controller a frame after `⌘W`, so every closed pane could leak an orphan process. | Returns a cached idle placeholder that never starts and is never registered. `BugReviewTests.testControllerForUnknownPaneNeverSpawns`. |
| 2 | high (security) | ⌘-click on a path called `NSWorkspace.open`, which executes scripts and binaries. | `LinkOpener`: files → text editor, directories → Finder, URLs → browser. `testLinkOpenerNeverExecutes`. |
| 3 | medium | `TerminalHostView.updateNSView` re-claimed first responder on every SwiftUI update. `contentVersion` ticks at up to 30 Hz while output flows, so the search field and palette would lose focus mid-keystroke. | First attempt (transition-only) regressed: the first update runs before the view has a window, so typing never worked. Final rule: claim whenever focused and the current first responder is not an `NSTextView` field editor. Verified by typing. |
| 4 | medium | `[shell] integration = false` was ignored — the launch factory always injected the shim. | Passes `nil` integration when off. Covered by `ShellLaunchBuilderTests.testIntegrationDisabledLeavesShellAlone` at the builder level. |
| 5 | low | `WorkspaceView` and `ScratchPaneHost` called `runtime.layout(for:)` inside `body`, creating state (and spawning a shell) during view evaluation. | Both use `existingLayout` and open the session from `onAppear`. |
| 6 | low | `closeSession` correctness re-checked: panes, controllers, and layout are all removed. | No change; `testCloseSessionCleansUp` pins it. |

## Checked and fine

- **Concurrency.** `onSemanticEvents` and `onSemanticEventSync` run on SwiftTerm's process queue; the only state they touch is `RunEventBus` (locked) and `PromptMarks` (locked). Everything else hops to main via `Task { @MainActor }`.
- **Lifetimes.** Every closure stored on a view or controller captures `[weak self]`. `TerminalHostView.Coordinator` removes its `NSEvent` monitor in `deinit`; `HotkeyPanelController` removes its observer and monitor in `deinit`; `ConfigWatcher.stop()` cancels the source, whose cancel handler closes the descriptor.
- **Process groups.** `terminate()` sends `SIGHUP` to the group and escalates to `SIGKILL` after 2 s; `prepareForQuit` calls it for every controller. `PTYIntegrationTests.testTerminateKillsARunningShell` checks the group leader is gone.
- **Persistence.** `state.json` is written atomically at `0600`; sessions are removed with their project; scrollback files are deleted with their session and wholesale when persistence is turned off.
- **Config.** Every Settings setter clamps (font 8–40, opacity ≤ 0.9); a malformed user theme is skipped with a log line and the app falls back to Ante Dark; a config that fails to parse after an edit is never written.

## Not done

- Split layouts are not persisted (by design).
- `SplitDivider` pushes/pops `NSCursor` on hover; a fast exit can leave the cursor pushed until the next hover. Cosmetic.
