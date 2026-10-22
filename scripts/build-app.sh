#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/CleanUP.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/CleanUP" "$app_dir/Contents/MacOS/CleanUP"
cp packaging/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/create-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Finder and synced folders can attach metadata that codesign rejects.
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "App lista: $app_dir"
