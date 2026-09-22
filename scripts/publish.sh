#!/bin/bash
# Publishes main's committed tree to GitHub as one commit on the `public` branch.
#
# Local `main` is never pushed: its history predates the open-source cleanup. `public` tracks
# origin/main and receives main's tree (index and working copy set from the commit, so
# untracked and ignored files such as docs/superpowers can never ride along), a personal-data
# scan runs, and the result is pushed. Whatever happens, main is checked out again on exit.
#
# Usage: scripts/publish.sh "<commit message>"
set -euo pipefail
cd "$(dirname "$0")/.."
msg="${1:?usage: scripts/publish.sh \"<commit message>\"}"
[ -z "$(git status --porcelain)" ] || { echo "main has uncommitted changes; commit or stash first"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "run from main"; exit 1; }
trap 'git checkout -q main 2>/dev/null || true' EXIT

git checkout -q public
git read-tree -u --reset main
if [ -n "$(git ls-files docs/superpowers)" ]; then
  echo "docs/superpowers is tracked; it must stay ignored"; exit 1
fi

# The leak guard learns this machine's names at run time, so the script itself never has to
# carry them. Generic patterns catch the artefacts that leaked once before.
pattern="var/folders|friction-log|raw\.bin|claude\.ai/code"
# Names are matched as whole tokens (not inside other words), and only when five characters or
# longer, so a login such as "mac" cannot block every publish.
add_name() {
  local n; n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  [ "${#n}" -lt 5 ] || pattern="$pattern|(^|[^a-z0-9])$n([^a-z0-9]|$)"
}
add_name "$(id -un)"
host="$(scutil --get LocalHostName 2>/dev/null || true)"
add_name "$host"
add_name "${host%-*}"                                       # "name-macbook" without the model suffix
add_name "$(scutil --get ComputerName 2>/dev/null || true)"
# The script names the patterns it looks for, so it is the one file left out of the scan.
hits="$(git grep -n -i -E "$pattern" -- . ':!scripts/publish.sh' || true)"
# Absolute home paths are only ever the synthetic fixtures /Users/t, /Users/x, /Users/me.
homes="$(git grep -n -E '/Users/[A-Za-z0-9_.-]+' -- . ':!scripts/publish.sh' | grep -v -E '/Users/(t|x|me)([/"'"'"']|$)' || true)"
if [ -n "$hits$homes" ]; then
  echo "personal or internal strings found in the tree; not publishing:"
  printf '%s\n' "$hits" "$homes" | grep . | head
  exit 1
fi
if git diff --cached --quiet; then
  echo "public already matches main; nothing to publish"
else
  git commit -q -m "$msg"
fi
git push origin public:main
echo "published $(git rev-parse --short public) → origin/main"
