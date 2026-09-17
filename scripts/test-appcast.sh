#!/bin/bash
# Checks that generate_appcast, run the way package.sh runs it, produces an appcast entry with
# the bundle's build number and a download URL under the release prefix. Uses a throwaway key
# (keychain account "ante-appcast-test") so the owner's real key is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$(scripts/sparkle-tools.sh)"
work="$(mktemp -d)"
cleanup() {
  rm -rf "$work"
  security delete-generic-password -a ante-appcast-test -s "https://sparkle-project.org" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# generate_appcast signs an archive only when the app's SUPublicEDKey matches the signing key,
# so the throwaway key goes into the dummy app's Info.plist.
"$bin/generate_keys" --account ante-appcast-test >/dev/null
pubkey="$("$bin/generate_keys" --account ante-appcast-test -p)"

app="$work/Ante.app/Contents"
mkdir -p "$app/MacOS" "$work/dist"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>ante.term</string>
<key>CFBundleShortVersionString</key><string>9.9.9</string>
<key>CFBundleVersion</key><string>4242</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>SUPublicEDKey</key><string>$pubkey</string>
</dict></plist>
PLIST
printf '#!/bin/sh\n' > "$app/MacOS/Ante"; chmod +x "$app/MacOS/Ante"
hdiutil create -quiet -volname Ante -srcfolder "$work/Ante.app" -ov -format UDZO "$work/dist/Ante.dmg"

"$bin/generate_appcast" --account ante-appcast-test \
  --download-url-prefix "https://github.com/ishan97/ante/releases/download/v9.9.9/" \
  -o "$work/appcast.xml" "$work/dist"

grep -q '<sparkle:version>4242</sparkle:version>' "$work/appcast.xml"
grep -q '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' "$work/appcast.xml"
grep -q 'url="https://github.com/ishan97/ante/releases/download/v9.9.9/Ante.dmg"' "$work/appcast.xml"
grep -q 'sparkle:edSignature=' "$work/appcast.xml"
echo "appcast OK"
