# Spikes

## Spike A — transparent SwiftTerm over a background (2026-09-09)

Question: can `TerminalView` render over a view behind it without a fork?

Result: **PASS**. `backgroundOpacity` on SwiftTerm 1.20.0 composites over whatever SwiftUI
places behind it in the same window. Verified with a `LinearGradient` behind the terminal at
opacity 0.6: gradient visible, glyphs crisp, prompt colours intact. Metal renderer: on
(`setUseMetal(true)` succeeded). Scroll-under-load was not measured in this spike — it needs
typed input, which the launch check could not automate; the wallpaper work checked it by hand
with `yes | head -n 5000`.

Decision: the wallpaper layer **ships**.

## Spike B — reaching OSC 133/7 (2026-09-09)

Answered without code: `LocalProcessTerminalView.dataReceived(slice:)` is `open` in
SwiftTerm 1.20.0, so `AnteTerminalView` tees every PTY byte through Ante's own scanner.
No dependence on SwiftTerm's OSC handler registration or on unreleased APIs.

Two things learned while wiring it that the plan did not predict:

- SwiftTerm 1.20.0's `processTerminated(exitCode:)` passes the raw `wait(2)` status
  (e.g. 768 for `exit 3`), not a normalized code. `TerminalSessionController` decodes it.
- SwiftTerm's `terminate()` only signals the shell; a foreground child survives. The
  controller signals the whole process group (SIGHUP, then SIGKILL after 2 s), like a
  closing terminal window does.
