#!/bin/sh
# Builds NeatEdit, puts it in ~/Applications and the `neatedit` command in ~/.local/bin.
set -eu
cd "$(dirname "$0")/.."

./scripts/build-app.sh
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$HOME/Applications/NeatEdit.app"
cp -R build/NeatEdit.app "$HOME/Applications/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/NeatEdit.app"
install -m 755 scripts/neatedit "$HOME/.local/bin/neatedit"
echo "Installed ~/Applications/NeatEdit.app and ~/.local/bin/neatedit"
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "Add ~/.local/bin to PATH to use neatedit" ;;
esac
