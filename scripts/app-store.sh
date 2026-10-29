#!/bin/sh
# Archives the sandboxed App Store build and uploads it to App Store Connect.
# Each upload needs a new CFBundleVersion in Resources/Info.plist.
# Needs xcodegen and the GTD team account signed in to Xcode.
#   ./scripts/app-store.sh           # archive + upload
#   ./scripts/app-store.sh export    # archive + build/export/NeatEdit.pkg only
set -eu
cd "$(dirname "$0")/.."

DESTINATION="${1:-upload}"
case "$DESTINATION" in
    upload|export) ;;
    *) echo "usage: $0 [upload|export]" >&2; exit 2 ;;
esac
xcodegen generate --quiet
rm -rf build/NeatEdit.xcarchive build/export
xcodebuild -project NeatEdit.xcodeproj -scheme NeatEditApp -configuration Release \
    -archivePath build/NeatEdit.xcarchive -allowProvisioningUpdates -quiet archive

OPTIONS=build/ExportOptions.plist
sed "s#__DESTINATION__#$DESTINATION#" scripts/ExportOptions.plist > "$OPTIONS"
xcodebuild -exportArchive -archivePath build/NeatEdit.xcarchive -exportOptionsPlist "$OPTIONS" \
    -exportPath build/export -allowProvisioningUpdates
