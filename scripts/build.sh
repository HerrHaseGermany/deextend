#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning | /usr/bin/grep -F -- "$SIGNING_IDENTITY" >/dev/null; then
    print -u2 "Signierzertifikat nicht verfügbar: $SIGNING_IDENTITY"
    print -u2 "CODE_SIGN_IDENTITY auf eine gültige Codesigning-Identität setzen."
    exit 1
fi
STAGING=$(mktemp -d /tmp/deextend-build.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Deextend.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/Deextend"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for LOCALIZATION in Resources/*.lproj; do
    ditto "$LOCALIZATION" "$APP/Contents/Resources/${LOCALIZATION:t}"
done
swift scripts/icon.swift "$STAGING"
iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --sign "$SIGNING_IDENTITY" --identifier de.christianraudzis.deextend "$APP"
codesign --verify --strict "$APP"
mkdir -p build
ditto --norsrc "$APP" build/Deextend.app
xattr -cr build/Deextend.app
# File Provider can immediately re-add Finder metadata inside Documents.
# The complete staged bundle was verified above, before this transport copy.
print "Fertig: $PWD/build/Deextend.app"
