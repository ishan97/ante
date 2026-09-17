#!/bin/bash
# Runs every test suite and builds the app.
set -euo pipefail
cd "$(dirname "$0")/.."

# If AnteCore changed since the dependents were last built, rebuild them from scratch: a test
# binary linked against an older AnteCore keeps the old enum layout (a stale enum layout once
# turned a zsh into "pi"), and SwiftPM does not always notice.
# On a fresh checkout there is no .build yet (and `find -newer` on a missing path would fail
# under pipefail), so test for the directory first.
if [ ! -d Packages/AnteTerm/.build ] || [ -n "$(find Packages/AnteCore/Sources -type f -newer Packages/AnteTerm/.build 2>/dev/null | head -n 1)" ]; then
  rm -rf Packages/AnteTerm/.build Packages/AnteUI/.build Packages/AntePanel/.build
fi

echo "== AnteCore"
swift test --package-path Packages/AnteCore 2>&1 | { grep -E "error:|failed|Executed .* tests" || true; } | tail -n 3

for pkg in AnteTerm AnteTheme AnteUI AntePanel; do
  echo "== $pkg"
  # A plain build first re-plans dependency sources; `swift test` alone can miss files newly
  # added to a path dependency and fail with "cannot find X in scope".
  swift build --package-path Packages/$pkg --build-tests > /dev/null 2>&1 || true
  swift test --package-path Packages/$pkg 2>&1 | { grep -E "error:|failed|Executed .* tests" || true; } | tail -n 3
done

if [ -x build/sparkle-tools/bin/generate_appcast ]; then
  echo "== appcast"
  scripts/test-appcast.sh
fi

./scripts/bootstrap.sh > /dev/null

echo "== App build"
xcodebuild -project Ante.xcodeproj -scheme Ante -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation -quiet build
echo "OK"
