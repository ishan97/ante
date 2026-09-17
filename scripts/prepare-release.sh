#!/bin/bash
# scripts/prepare-release.sh <version>
# Stamps project.yml with the marketing version and a build number (the commit count, which
# Sparkle compares), regenerates the Xcode project, commits on main, publishes the tree to the
# public branch and tags it v<version>. Then archive in Xcode (Product → Archive → Distribute App →
# Direct Distribution → Export) and run scripts/dmg-from-app.sh on the exported app.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: scripts/prepare-release.sh <version>   e.g. 1.0.1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "run from main"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "main has uncommitted changes; commit or stash first"; exit 1; }
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null && [ "${ANTE_RETAG:-0}" != "1" ]; then
  echo "tag v$version already exists; use a new version or ANTE_RETAG=1 to move it"; exit 1
fi

# The release commit itself counts, so the build number is the current count plus one.
build="$(( $(git rev-list --count HEAD) + 1 ))"
perl -pi -e "s/^(\s*CFBundleShortVersionString:).*/\$1 \"$version\"/; s/^(\s*CFBundleVersion:).*/\$1 \"$build\"/" project.yml
grep -E "CFBundleShortVersionString|CFBundleVersion" project.yml
./scripts/bootstrap.sh > /dev/null
git add project.yml Ante/Info.plist
git commit -q -m "release: $version ($build)"
scripts/publish.sh "release: $version ($build)"
git tag ${ANTE_RETAG:+-f} -a "v$version" -m "Ante $version" public
git push ${ANTE_RETAG:+--force} origin "v$version"
echo
echo "== ready to archive $version ($build)"
echo "   Xcode: Product → Archive → Distribute App → Direct Distribution → Upload; when notarized, Export"
echo "   then: scripts/dmg-from-app.sh <exported Ante.app>"
