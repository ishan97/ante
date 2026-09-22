#!/bin/bash
# Publishes main's committed tree to GitHub as one commit on the `public` branch.
#
# Local `main` is never pushed: its history predates the open-source cleanup. `public` tracks
# origin/main and receives main's tree (index and working copy set from the commit, so
# untracked and ignored files such as docs/superpowers can never ride along), a personal-data
# scan runs, and the result is pushed.
#
# Usage: scripts/publish.sh "<commit message>"
set -euo pipefail
cd "$(dirname "$0")/.."
msg="${1:?usage: scripts/publish.sh \"<commit message>\"}"
[ -z "$(git status --porcelain)" ] || { echo "main has uncommitted changes; commit or stash first"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "run from main"; exit 1; }

git checkout -q public
git read-tree -u --reset main
if [ -n "$(git ls-files docs/superpowers)" ]; then
  echo "docs/superpowers is tracked; it must stay ignored"; git checkout -q main; exit 1
fi
if git grep -q -i -E "sherlock|fritz\.box|ishans-macbook|var/folders|friction-log|raw\.bin|claude\.ai/code" -- . ':!scripts/publish.sh' 2>/dev/null; then
  echo "personal or internal strings found in the tree; not publishing:"
  git grep -n -i -E "sherlock|fritz\.box|ishans-macbook|var/folders|friction-log|raw\.bin|claude\.ai/code" -- . ':!scripts/publish.sh' | head
  git checkout -q main
  exit 1
fi
if git diff --cached --quiet; then
  echo "public already matches main; nothing to publish"
else
  git commit -q -m "$msg"
fi
git push origin public:main
git checkout -q main
echo "published $(git rev-parse --short public) → origin/main"
