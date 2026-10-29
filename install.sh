#!/bin/bash
# Build the app, install the hook script, register it in ~/.claude/settings.json and
# start the menu bar list at login.
# Idempotent: running it again rebuilds the app and leaves a single hook entry per event.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
hook="$HOME/.claude/hooks/session-drawer.sh"
settings="$HOME/.claude/settings.json"
app="$HOME/Applications/SessionDrawer.app"
label="io.github.msziva.session-drawer"
agent="$HOME/Library/LaunchAgents/$label.plist"

command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }

bash "$repo/build.sh"

mkdir -p "$HOME/.claude/hooks"
cp "$repo/hooks/notify.sh" "$hook"
chmod +x "$hook"

[ -f "$settings" ] || echo '{}' > "$settings"
backup="$settings.bak.$(date +%Y%m%d%H%M%S)"
cp "$settings" "$backup"

# Stop and the prompts that wait for you notify; the other events only keep the list current.
cmd="bash $hook"
tmp=$(mktemp)
jq --arg cmd "$cmd" '
  def entry(matcher): {hooks: [{type: "command", command: $cmd, timeout: 10, async: true}]}
                      + (if matcher then {matcher: matcher} else {} end);
  def without_ours: map(select(all(.hooks[]?; .command != $cmd)));
  def register(event; matcher): .hooks[event] = ((.hooks[event] // []) | without_ours) + [entry(matcher)];
  .hooks //= {}
  | register("Stop"; null)
  | register("Notification"; "permission_prompt|elicitation_dialog")
  | register("SessionStart"; null)
  | register("UserPromptSubmit"; null)
  | register("PostToolUse"; null)
  | register("SessionEnd"; null)
' "$settings" > "$tmp"
mv "$tmp" "$settings"

# Start the menu bar list at login, and now.
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent"

echo "Hook installed: $hook"
echo "Settings updated: $settings (backup: $backup)"
echo "Menu bar list started; it starts at login via $agent"
echo "Restart running Claude Code sessions (or open /hooks once) to pick up the hooks."
