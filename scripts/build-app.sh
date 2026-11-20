#!/bin/sh
# Builds a release NeatEdit.app into ./build
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product NeatEdit
BIN="$(swift build -c release --show-bin-path)/NeatEdit"

APP=build/NeatEdit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM stamps the binary with the deployment target as its SDK, and macOS
# then gives the app the old look (tab bar, toolbar). Xcode builds, which is
# what ships, carry the real SDK; make this build match them.
SDK="$(xcrun --sdk macosx --show-sdk-version)"
MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
xcrun vtool -set-build-version macos "$MINOS" "$SDK" -replace -output "$APP/Contents/MacOS/NeatEdit" "$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp scripts/neatedit "$APP/Contents/Resources/neatedit"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
