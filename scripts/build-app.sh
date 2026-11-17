#!/bin/zsh
# Builds dist/LangCursor.app and ad-hoc signs it.
set -euo pipefail

cd "${0:a:h}/.."

swift build -c release
bin_path="$(swift build -c release --show-bin-path)"

app="dist/LangCursor.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$bin_path/LangCursor" "$app/Contents/MacOS/LangCursor"
# Package resources travel with the application instead of depending on the build directory.
for resource_bundle in "$bin_path"/*.bundle(N); do
    cp -R "$resource_bundle" "$app/Contents/Resources/"
done
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier com.yekinya.langcursor "$app"

echo "Built $app"
