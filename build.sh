#!/bin/zsh
# Builds Void.app and installs it into /Applications.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
APP="build/Void.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/uk.lproj" "$APP/Contents/Resources/en.lproj"
cp .build/release/VoidApp "$APP/Contents/MacOS/Void"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ ! -f Resources/AppIcon.icns ]]; then
  T=$(mktemp -d); swift scripts/icon.swift "$T/icon.png"
  mkdir "$T/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
rm -rf "/Applications/Void.app"; cp -R "$APP" /Applications/
echo "Installed /Applications/Void.app"
