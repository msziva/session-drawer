#!/bin/bash
# Remove the app, the hook script and its entries from ~/.claude/settings.json.
set -euo pipefail
hook="$HOME/.claude/hooks/term-tab-notify.sh"
settings="$HOME/.claude/settings.json"
cmd="bash $hook"

if [ -f "$settings" ]; then
  cp "$settings" "$settings.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  jq --arg cmd "$cmd" '
    def without_ours: map(select(all(.hooks[]?; .command != $cmd)));
    if .hooks then
      .hooks.Stop |= ((. // []) | without_ours)
      | .hooks.Notification |= ((. // []) | without_ours)
      | .hooks |= with_entries(select(.value != []))
    else . end
  ' "$settings" > "$tmp"
  mv "$tmp" "$settings"
fi

rm -f "$hook"
rm -rf "$HOME/Applications/TermTabNotify.app"
echo "Uninstalled. Notification permission can be removed in System Settings → Notifications."
