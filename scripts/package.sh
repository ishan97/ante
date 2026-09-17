#!/bin/bash
# Builds Ante for release, signs it, and wraps it in a DMG under dist/.
# Signing: ad-hoc by default. For distribution set ANTE_SIGN_IDENTITY="Developer ID Application: …"
# (or ANTE_SIGN_IDENTITY=auto to pick the first Developer ID identity in the keychain). With a
# notarytool keychain profile (ANTE_NOTARY_PROFILE, default "ante", created once with
# `xcrun notarytool store-credentials ante`), the DMG is also notarized and stapled, so it opens
# on any Mac without Gatekeeper's warning. ANTE_NOTARIZE=0 skips the notary submission (a Developer ID
# signature still fetches a timestamp from Apple).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bootstrap.sh > /dev/null

identity="${ANTE_SIGN_IDENTITY:--}"
if [ "$identity" = "auto" ]; then
  identity="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -n 1 | tr -d '"')"
  [ -z "$identity" ] && { echo "no Developer ID Application identity in the keychain"; exit 1; }
fi
notary_profile="${ANTE_NOTARY_PROFILE:-ante}"
version="$(grep CFBundleShortVersionString project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
[ -z "$version" ] && version="0.0.0"

echo "== building Release"
xcodebuild -project Ante.xcodeproj -scheme Ante -configuration Release \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath build/DerivedData -quiet build
app="build/DerivedData/Build/Products/Release/Ante.app"

# Build number = commits on this branch, so every packaged build is distinguishable in About
# and crash logs without anyone editing project.yml.
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
echo "== version $version ($build)"

echo "== signing with: $identity"
if [ "$identity" = "-" ]; then timestamp="--timestamp=none"; else timestamp="--timestamp"; fi
codesign --force --deep --options runtime "$timestamp" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements - "$app" 2>/dev/null | head -n 20

echo "== dmg"
mkdir -p dist build/dmg
rm -rf build/dmg/*
cp -R "$app" build/dmg/
ln -s /Applications build/dmg/Applications
dmg="dist/Ante-$version.dmg"
rm -f dist/*.dmg
hdiutil create -quiet -volname "Ante" -srcfolder build/dmg -ov -format UDZO "$dmg"
echo "== $dmg ($(du -h "$dmg" | cut -f1))"
if [ "$identity" = "-" ]; then
  echo "note: ad-hoc signed. Gatekeeper will warn on other Macs until signed with a Developer ID and notarized."
  exit 0
fi

if [ "${ANTE_NOTARIZE:-1}" = "0" ]; then
  echo "note: ANTE_NOTARIZE=0 — signed with '$identity', not sent to Apple. Runs on this Mac; other Macs still see Gatekeeper's warning."
elif xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
  echo "== notarizing (profile: $notary_profile)"
  xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$dmg"
  echo "== Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg" || true
else
  echo "note: signed with a Developer ID but not notarized (no notarytool profile '$notary_profile')."
  echo "      once: xcrun notarytool store-credentials $notary_profile --apple-id <id> --team-id <team> --password <app-specific password>"
fi

echo "== appcast"
# Every release ships the DMG under the same asset name, so the "latest" link never changes:
# https://github.com/ishan97/ante/releases/latest/download/Ante.dmg
cp -f "$dmg" dist/Ante.dmg
sparkle_bin="$(scripts/sparkle-tools.sh)"
"$sparkle_bin/generate_appcast" \
  --download-url-prefix "https://github.com/ishan97/ante/releases/download/v$version/" \
  -o appcast.xml dist/
echo "appcast.xml updated for $version ($build)."
echo
echo "next:"
echo "  gh release create v$version dist/Ante.dmg --title \"Ante $version\" --notes \"...\""
echo "  git checkout public && git checkout main -- . && git commit -am \"Ante $version\" && git push origin public:main && git checkout main"
