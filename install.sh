#!/bin/bash
# Build the app, install the hook script and register it in ~/.claude/settings.json.
# Idempotent: running it again rebuilds the app and leaves a single hook entry.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
hook="$HOME/.claude/hooks/term-tab-notify.sh"
settings="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }

bash "$repo/build.sh"

mkdir -p "$HOME/.claude/hooks"
cp "$repo/hooks/notify.sh" "$hook"
chmod +x "$hook"

[ -f "$settings" ] || echo '{}' > "$settings"
backup="$settings.bak.$(date +%Y%m%d%H%M%S)"
cp "$settings" "$backup"

cmd="bash $hook"
tmp=$(mktemp)
jq --arg cmd "$cmd" '
  def entry(matcher): {hooks: [{type: "command", command: $cmd, timeout: 10, async: true}]}
                      + (if matcher then {matcher: matcher} else {} end);
  def without_ours: map(select(all(.hooks[]?; .command != $cmd)));
  .hooks //= {}
  | .hooks.Stop = ((.hooks.Stop // []) | without_ours) + [entry(null)]
  | .hooks.Notification = ((.hooks.Notification // []) | without_ours)
                          + [entry("permission_prompt|elicitation_dialog")]
' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "Hook installed: $hook"
echo "Settings updated: $settings (backup: $backup)"
echo "Restart running Claude Code sessions (or open /hooks once) to pick up the hooks."
