#!/bin/sh
# Builds a release SimpleTextEdit.app into ./build
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product SimpleTextEdit
BIN="$(swift build -c release --show-bin-path)/SimpleTextEdit"

APP=build/SimpleTextEdit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SimpleTextEdit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
