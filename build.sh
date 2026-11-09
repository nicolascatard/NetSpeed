#!/bin/zsh
# Compile NetSpeed.app (universelle : Apple Silicon + Intel).
# Usage : ./build.sh            -> crée NetSpeed.app dans ce dossier
#         ./build.sh --install  -> et l'installe dans ~/Applications
set -e
cd "$(dirname "$0")"
APP=NetSpeed.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources

# Icône : icon.png (1024 px) -> AppIcon.icns
[ -f icon.png ] || swift icon.swift icon.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns
rm -rf AppIcon.iconset

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NetSpeed</string>
  <key>CFBundleIdentifier</key><string>local.netspeed</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>NetSpeed</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Binaire universel
TMP=$(mktemp -d)
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13 main.swift -o $TMP/NetSpeed-$arch \
    -framework AppKit -framework SystemConfiguration -framework ServiceManagement
done
lipo -create $TMP/NetSpeed-arm64 $TMP/NetSpeed-x86_64 -output $APP/Contents/MacOS/NetSpeed
rm -rf $TMP
codesign --force -s - $APP
echo "OK : $(pwd)/$APP"

if [[ "$1" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/$APP
  cp -R $APP ~/Applications/
  echo "Installé dans ~/Applications/$APP"
fi
