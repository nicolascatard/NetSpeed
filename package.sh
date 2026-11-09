#!/bin/zsh
# Crée NetSpeed.dmg, l'installeur à partager (ou à publier dans les Releases GitHub).
set -e
cd "$(dirname "$0")"
./build.sh
rm -rf dist NetSpeed.dmg
mkdir dist
cp -R NetSpeed.app dist/
ln -s /Applications dist/Applications   # raccourci pour glisser-déposer
hdiutil create -volname NetSpeed -srcfolder dist -ov -format UDZO NetSpeed.dmg >/dev/null
rm -rf dist
echo "OK : $(pwd)/NetSpeed.dmg"
