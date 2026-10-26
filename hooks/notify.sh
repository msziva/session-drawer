#!/bin/bash
# Claude Code Stop / Notification hook: posts a notification through TermTabNotify.app.
# Title: session name (/rename), else the Terminal tab title (session topic), else the
# project folder; body: event + last prompt snippet.
input=$(cat)

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
message=$(printf '%s' "$input" | jq -r '.message // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')

# Walk up the process tree to the first ancestor with a controlling tty (the claude process).
tty=""
pid=$PPID
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  t=$(ps -o tty= -p "$pid" | tr -d ' ')
  if [ -n "$t" ] && [ "$t" != "??" ]; then tty="/dev/$t"; break; fi
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done

label=""
prompt=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  label=$(grep '"custom-title"' "$transcript" | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null)
  prompt=$(tail -n 400 "$transcript" \
    | jq -r 'select(.type == "user" and (.message.content | type) == "string") | .message.content' 2>/dev/null \
    | grep -v '^<' | tail -n 1 | tr '\n' ' ' | cut -c 1-90)
fi

# No /rename: use the Terminal.app tab title (Claude Code sets it to the session topic),
# minus the leading status glyph (✳ idle, ◐ working, ...).
if [ -z "$label" ] && [ -n "$tty" ] && [ "$TERM_PROGRAM" = "Apple_Terminal" ]; then
  label=$(osascript -e "tell application \"Terminal\"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is \"$tty\" then return custom title of t
      end repeat
    end repeat
  end tell" 2>/dev/null | sed -E 's/^[^[:alnum:]]*[[:space:]]+//')
  case "$label" in Terminal|"Claude Code") label="" ;; esac
fi
[ -z "$label" ] && label=$(basename "$cwd")

if [ "$event" = "Stop" ]; then
  status="✅ Done"
  sound="Glass"
else
  status="⏳ ${message:-Waiting for you}"
  sound="Ping"
fi

body="$status"
[ -n "$prompt" ] && body="$status — $prompt"

# Detached so a first-run permission prompt is not killed by the hook timeout.
nohup "$HOME/Applications/TermTabNotify.app/Contents/MacOS/TermTabNotify" \
  --title "Claude · $label" --body "$body" --id "$session_id" --tty "$tty" >/dev/null 2>&1 &
nohup afplay "/System/Library/Sounds/$sound.aiff" >/dev/null 2>&1 &
exit 0
