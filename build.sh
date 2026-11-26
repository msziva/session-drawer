#!/bin/bash
# Build and sign SessionDrawer.app into ~/Applications.
# Signed with your own certificate when the keychain has one (Developer ID Application or
# Apple Development; SESSION_DRAWER_SIGN_IDENTITY picks a specific one), else ad-hoc.
# With a certificate the app keeps its identity across rebuilds, so macOS keeps the
# Accessibility permission; an ad-hoc signed build is a new app to it every time.
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
identity="${SESSION_DRAWER_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Developer ID Application|Apple Development/ { print $2; exit }')
fi
if [ -n "$identity" ]; then
  # No timestamp: that needs the network, and only matters for distributing the app.
  codesign --force --timestamp=none --sign "$identity" "$app"
else
  codesign --force --sign - "$app"
  echo "Signed ad-hoc: allow the app again under Accessibility after each rebuild"
fi
# Register with LaunchServices so notification clicks can relaunch the app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Built $app"
