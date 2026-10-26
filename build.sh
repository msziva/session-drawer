#!/bin/bash
# Build and ad-hoc sign TermTabNotify.app into ~/Applications.
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/src"
app="$HOME/Applications/TermTabNotify.app"

command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install' first" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$src/Info.plist" "$app/Contents/Info.plist"
swiftc -O -o "$app/Contents/MacOS/TermTabNotify" "$src/main.swift"
codesign --force --sign - "$app"
# Register with LaunchServices so notification clicks can relaunch the app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "Built $app"
