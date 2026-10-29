#!/bin/bash
# Remove the app, the login item, the hook script and its entries from ~/.claude/settings.json.
set -euo pipefail
hook="$HOME/.claude/hooks/session-drawer.sh"
settings="$HOME/.claude/settings.json"
label="io.github.msziva.session-drawer"
agent="$HOME/Library/LaunchAgents/$label.plist"
cmd="bash $hook"

if [ -f "$settings" ]; then
  cp "$settings" "$settings.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  jq --arg cmd "$cmd" '
    def without_ours: map(select(all(.hooks[]?; .command != $cmd)));
    if .hooks then
      .hooks |= with_entries(.value |= without_ours | select(.value != []))
    else . end
  ' "$settings" > "$tmp"
  mv "$tmp" "$settings"
fi

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$agent"
pkill -x SessionDrawer 2>/dev/null || true
rm -f "$hook"
rm -rf "$HOME/Applications/SessionDrawer.app"
rm -rf "$HOME/Library/Application Support/SessionDrawer"
echo "Uninstalled. Notification permission can be removed in System Settings → Notifications."
