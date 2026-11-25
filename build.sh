#!/bin/bash
# Build and ad-hoc sign SessionDrawer.app into ~/Applications.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
src="$root/src"
app="$HOME/Applications/SessionDrawer.app"

command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install' first" >&2; exit 1; }

# Stop the running menu bar instance: it would keep the old binary.
pkill -x SessionDrawer 2>/dev/null || true

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$src/Info.plist" "$app/Contents/Info.plist"
# The icon is drawn by icon/make-icon.swift: run that to change it.
cp "$root/icon/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
swiftc -O -o "$app/Contents/MacOS/SessionDrawer" "$src"/*.swift
codesign --force --sign - "$app"
# Register with LaunchServices so notification clicks can relaunch the app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Built $app"
