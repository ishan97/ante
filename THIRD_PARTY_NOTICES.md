# Third-party notices

Ante is MIT licensed (see `LICENSE`). It builds on, bundles, or interoperates with the work
below. Each item keeps its own licence; none of it is relicensed by Ante.

## Swift packages (pinned in `Packages/*/Package.swift`)

| Package | Licence | Used for |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.20.0 | MIT | the terminal emulator and PTY |
| [TOMLKit](https://github.com/LebJe/TOMLKit) 0.6.0 | MIT | reading `config.toml` and theme files |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.0.1 | MIT | the global show/hide hotkey |

`swift-argument-parser` (Apache-2.0) appears in `Package.resolved` because SwiftTerm's `termcast`
example tool depends on it; Ante links only the SwiftTerm library, so nothing Apache-licensed
ships in the app.

## Bundled font

- [JetBrains Mono](https://www.jetbrains.com/lp/mono/), © 2020 The JetBrains Mono Project
  Authors, SIL Open Font License 1.1 — `Packages/AnteTheme/Sources/AnteTheme/Resources/Fonts/OFL.txt`.

## Bundled colour schemes

The palettes under `Packages/AnteTheme/Sources/AnteTheme/Resources/Themes` other than Ante Dark
and Ante Light reproduce published colour values from these projects:

| Theme | Source | Licence |
|---|---|---|
| Catppuccin Mocha | [catppuccin/catppuccin](https://github.com/catppuccin/catppuccin) | MIT |
| Gruvbox Dark | [morhetz/gruvbox](https://github.com/morhetz/gruvbox) | MIT |
| One Dark | [atom/one-dark-syntax](https://github.com/atom/one-dark-syntax) | MIT |
| Solarized Dark | [altercation/solarized](https://github.com/altercation/solarized) | MIT |

## Protocols and file formats

Ante implements published conventions and reads other tools' files; it contains no code from
those projects:

- OSC 133 (semantic prompt marks) and OSC 7 (working directory), as documented by iTerm2,
  VS Code and Ghostty; OSC 9 desktop notifications. The shell integration scripts under
  `Packages/AnteTerm/Sources/AnteTerm/Resources/Integration` are original.
- `.itermcolors` (iTerm2) and Alacritty `.toml` colour schemes, imported through
  `Packages/AnteTheme/Sources/AnteTheme/Importers`.
- Session and history files written by Claude Code, Codex, OpenCode and Pi, read read-only to
  populate the Sessions board.

Product names above belong to their owners and are used only to identify compatibility.
