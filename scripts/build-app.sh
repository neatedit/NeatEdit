#!/bin/sh
# Builds a release NeatEdit.app into ./build
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product NeatEdit
BIN="$(swift build -c release --show-bin-path)/NeatEdit"

APP=build/NeatEdit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeatEdit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp scripts/neatedit "$APP/Contents/Resources/neatedit"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
