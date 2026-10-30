#!/bin/sh
# Builds build/NeatEdit-<version>.dmg for direct download: the sandboxed app,
# signed with Developer ID, notarized by Apple and stapled.
# Needs xcodegen and the GTD team account signed in to Xcode.
set -eu
cd "$(dirname "$0")/.."

ARCHIVE=build/NeatEdit-dmg.xcarchive
EXPORT=build/dmg-export
VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
DMG=build/NeatEdit-$VERSION.dmg

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT" "$DMG"
xcodebuild -project NeatEdit.xcodeproj -scheme NeatEditApp -configuration Release \
    -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive

# Signs with Developer ID and sends the app to Apple's notary service.
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions-DeveloperID.plist \
    -exportPath "$EXPORT" -allowProvisioningUpdates

# Apple usually answers within minutes; give up after an hour.
tries=0
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT" >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 120 ] || { echo "notarization didn't finish in an hour" >&2; exit 1; }
    echo "waiting for notarization ($tries)..."
    sleep 30
done

APP=$EXPORT/NeatEdit.app
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

FOLDER=$(mktemp -d -t neatedit-dmg)
trap 'rm -rf "$FOLDER"' EXIT
ditto "$APP" "$FOLDER/NeatEdit.app"
ln -s /Applications "$FOLDER/Applications"
hdiutil create -quiet -volname NeatEdit -srcfolder "$FOLDER" -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"
shasum -a 256 "$DMG"
