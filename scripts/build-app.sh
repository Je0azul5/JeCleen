#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/JeCleen.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
# Replace the executable atomically so rebuilding does not overwrite a running binary.
cp "$binary_dir/JeCleen" "$app_dir/Contents/MacOS/JeCleen.new"
mv -f "$app_dir/Contents/MacOS/JeCleen.new" "$app_dir/Contents/MacOS/JeCleen"
cp packaging/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/create-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Finder and synced folders can attach metadata that codesign rejects.
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "App lista: $app_dir"
