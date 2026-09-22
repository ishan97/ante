# Security

Ante runs shells and reads files written by other tools, so we take reports seriously.

Please do not open a public issue for a vulnerability. Use GitHub's private vulnerability
reporting on this repository (Security → Report a vulnerability). If that option is not
visible, open an issue that says only "security report, please contact me" and a maintainer
will reach out for the details.

What Ante does, so you know what is in scope:

- It writes under `~/Library/Application Support/Ante` and `~/.config/ante`; the updater
  (Sparkle) keeps its preferences in `~/Library/Preferences/ante.term.plist` and downloads into
  `~/Library/Caches/ante.term`. Only when you opt in from Settings → Agents does it add three
  hooks to `~/.claude/settings.json` (backed up first, removable from the same place).
- Its only network traffic is the daily update check (an HTTPS fetch of `appcast.xml` from this
  repository), which Settings → General → Updates turns off, and the release download from
  GitHub, which only ever happens after you click Install.
- Everything it shows from a terminal, an agent's session file, or a hook is treated as
  untrusted: control characters are stripped, lengths are capped, and nothing from those
  sources is executed. `docs/security-review.md` lists the checks.
