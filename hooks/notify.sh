#!/bin/bash
# Claude Code hook for session-drawer.
# Every event updates the session's state file, which the menu bar list reads.
# Stop and Notification events also post a notification through SessionDrawer.app.
# Notification title: session name (/rename), else the Terminal tab title (session topic),
# else the project folder; body: event + last prompt snippet.
input=$(cat)

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

state_dir="$HOME/Library/Application Support/SessionDrawer/sessions"
state_file="$state_dir/$session_id.json"
now=$(date +%s)

# Writes the state file atomically: merges the jq filter's output into the old state.
write_state() {
  mkdir -p "$state_dir"
  local old='{}'
  [ -f "$state_file" ] && jq -e . "$state_file" >/dev/null 2>&1 && old=$(cat "$state_file")
  local tmp="$state_file.$$.tmp"
  printf '%s' "$old" | jq "$@" > "$tmp" && mv "$tmp" "$state_file" || rm -f "$tmp"
}

# A tool call after a permission prompt means the session is working again.
# Runs on every tool call, so it returns before doing anything expensive.
if [ "$event" = "PostToolUse" ]; then
  [ -f "$state_file" ] && [ "$(jq -r '.status // empty' "$state_file" 2>/dev/null)" = "waiting" ] || exit 0
  write_state --argjson now "$now" '.status = "working" | .updated_at = $now | .message = null'
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
message=$(printf '%s' "$input" | jq -r '.message // empty')
submitted=$(printf '%s' "$input" | jq -r '.prompt // empty')

# Walk up the process tree to the first ancestor with a controlling tty (the claude process),
# remembering our own ancestors so they are not mistaken for background tasks below.
tty=""
claude_pid=""
ancestors=" $$ "
pid=$PPID
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  t=$(ps -o tty= -p "$pid" | tr -d ' ')
  if [ -n "$t" ] && [ "$t" != "??" ]; then tty="/dev/$t"; claude_pid=$pid; break; fi
  ancestors="$ancestors$pid "
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done

# A finished turn while background tasks (run_in_background commands, monitors) are still
# running is just a progress update: the session is still working.
# Claude Code runs each tool command in a shell sourced from ~/.claude/shell-snapshots.
background=0
if [ "$event" = "Stop" ] && [ -n "$claude_pid" ]; then
  background=$(ps -A -o pid=,ppid=,command= \
    | awk -v parent="$claude_pid" -v skip="$ancestors" \
        '$2 == parent && /shell-snapshots/ && index(skip, " " $1 " ") == 0' | wc -l | tr -d ' ')
fi

# Is this session's tab the one you are looking at?
front=false
if [ -n "$tty" ] && [ "$TERM_PROGRAM" = "Apple_Terminal" ] \
   && { [ "$event" = "Stop" ] || [ "$event" = "Notification" ]; }; then
  front_tty=$(osascript -e 'tell application "Terminal" to if frontmost then tty of selected tab of front window' 2>/dev/null)
  [ "$front_tty" = "$tty" ] && front=true
fi

label=""
prompt="$submitted"
answer=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  label=$(grep '"custom-title"' "$transcript" | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null)
  if [ -z "$prompt" ]; then
    prompt=$(tail -n 400 "$transcript" \
      | jq -r 'select(.type == "user" and (.message.content | type) == "string") | .message.content' 2>/dev/null \
      | grep -v '^<' | tail -n 1)
  fi
  if [ "$event" = "Stop" ]; then
    answer=$(tail -n 400 "$transcript" \
      | jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null \
      | tail -n 1 | jq -r '.' 2>/dev/null)
  fi
fi
prompt=$(printf '%s' "$prompt" | tr '\n' ' ' | cut -c 1-200)
answer=$(printf '%s' "$answer" | tr -d '*`#' | tr '\n' ' ' | tr -s ' ' | cut -c 1-200)

case "$event" in
  SessionStart) status="idle" ;;
  UserPromptSubmit) status="working" ;;
  Notification) status="waiting" ;;
  Stop) if [ "$background" -gt 0 ]; then status="working"; else status="done"; fi ;;
  SessionEnd) status="ended" ;;
  *) status="" ;;
esac

if [ -n "$status" ]; then
  write_state \
    --arg session_id "$session_id" --arg event "$event" --arg status "$status" \
    --arg home "$HOME" --arg cwd "$cwd" --arg transcript "$transcript" \
    --arg tty "$tty" --arg pid "$claude_pid" \
    --arg label "$label" --arg prompt "$prompt" --arg answer "$answer" --arg message "$message" \
    --argjson now "$now" --argjson front "$front" '
    def nonempty: if . == "" then null else . end;
    {
      session_id: $session_id,
      home: $home,
      cwd: (($cwd | nonempty) // .cwd),
      transcript: (($transcript | nonempty) // .transcript),
      tty: (($tty | nonempty) // .tty),
      pid: (($pid | tonumber?) // .pid),
      started_at: (.started_at // $now),
      updated_at: $now,
      status: $status,
      label: (($label | nonempty) // .label),
      last_prompt: (($prompt | nonempty) // .last_prompt),
      last_prompt_at: (if $event == "UserPromptSubmit" then $now else .last_prompt_at end),
      last_answer: (if $event == "Stop" then ($answer | nonempty) // .last_answer
                    elif $event == "UserPromptSubmit" then null
                    else .last_answer end),
      message: (if $status == "waiting" then ($message | nonempty) else null end),
      seen: $front,
      events: (((.events // []) + [{t: $now, event: $event, status: $status}]) | .[-20:])
    }'
fi

# Notifications only for a finished turn or a prompt that waits for you.
[ "$event" = "Stop" ] || [ "$event" = "Notification" ] || exit 0
# A turn that ended with background tasks still running: wait for the turn after they finish.
[ "$event" = "Stop" ] && [ "$background" -gt 0 ] && [ -z "$SESSION_DRAWER_EVERY_TURN" ] && exit 0
# Stay quiet when this session's tab is in front: you are already looking at it.
[ "$front" = true ] && exit 0

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
  status_text="✅ Done"
  sound="Glass"
else
  status_text="⏳ ${message:-Waiting for you}"
  sound="Ping"
fi

body="$status_text"
snippet=$(printf '%s' "$prompt" | cut -c 1-90)
[ -n "$snippet" ] && body="$status_text — $snippet"

# Detached so a first-run permission prompt is not killed by the hook timeout.
nohup "$HOME/Applications/SessionDrawer.app/Contents/MacOS/SessionDrawer" \
  --title "Claude · $label" --body "$body" --id "$session_id" --tty "$tty" >/dev/null 2>&1 &
nohup afplay "/System/Library/Sounds/$sound.aiff" >/dev/null 2>&1 &
exit 0
