#!/bin/bash
# scripts/dmg-from-app.sh <path/to/Ante.app> [out.dmg]
# Wraps an app you exported from Xcode's Organizer (already signed and, with Direct Distribution,
# notarized) in the same drag-to-Applications DMG that package.sh produces, and staples the
# notarization ticket to the DMG if the app carries one. Then signs the DMG for Sparkle and
# updates appcast.xml, and prints the two commands that finish the release.
set -euo pipefail
app="${1:?usage: dmg-from-app.sh <Ante.app> [out.dmg]}"
version="$(/usr/libexec/PlistBuddy -c "Print:CFBundleShortVersionString" "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c "Print:CFBundleVersion" "$app/Contents/Info.plist")"
out="${2:-dist/Ante-$version.dmg}"
stage="$(mktemp -d)/dmg"; mkdir -p "$stage" "$(dirname "$out")"
cp -R "$app" "$stage/"; ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -quiet -volname "Ante" -srcfolder "$stage" -ov -format UDZO "$out"
echo "== $out (version $version, build $build)"
codesign -dv "$app" 2>&1 | grep -E "^Authority=" | head -n 1 || true
if xcrun stapler validate "$app" >/dev/null 2>&1; then
  xcrun stapler staple "$out" >/dev/null && echo "== notarization ticket stapled to the DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$out" 2>&1 | tail -n 1
else
  echo "== app is not notarized: other Macs will still see Gatekeeper's warning"
fi

echo "== appcast"
# Every release ships the DMG under the same asset name, so the "latest" link never changes:
# https://github.com/ishan97/ante/releases/latest/download/Ante.dmg
rm -f dist/*.dmg.bak
cp -f "$out" dist/Ante.dmg
sparkle_bin="$(scripts/sparkle-tools.sh)"
feed="$(mktemp -d)/feed"; mkdir -p "$feed"; cp dist/Ante.dmg "$feed/"
"$sparkle_bin/generate_appcast" \
  --download-url-prefix "https://github.com/ishan97/ante/releases/download/v$version/" \
  -o appcast.xml "$feed"
echo "appcast.xml updated for $version ($build)."
echo
echo "next:"
echo "  gh release create v$version dist/Ante.dmg --title \"Ante $version\" --notes \"...\""
echo "  git commit -am \"release: $version appcast\" && scripts/publish.sh \"release: $version appcast\""
