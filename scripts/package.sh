#!/bin/zsh
# Builds Void.app and wraps it into dist/Void-<version>.dmg for a GitHub release.
set -e
cd "$(dirname "$0")/.."
./build.sh
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
mkdir -p dist
STAGE=$(mktemp -d)
cp -R build/Void.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "dist/Void-$VER.dmg"
hdiutil create -volname "Void $VER" -srcfolder "$STAGE" -ov -format UDZO "dist/Void-$VER.dmg" >/dev/null
(cd build && ditto -c -k --keepParent Void.app "../dist/Void-$VER.zip")
echo "dist/Void-$VER.dmg"
