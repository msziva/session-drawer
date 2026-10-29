# Session Drawer

A macOS menu bar list of your [Claude Code](https://claude.com/claude-code) sessions running in **Terminal.app**, plus notifications when one finishes or needs you. Click a session in the list, or its notification, and it switches to the exact tab it runs in.

When you run several Claude Code sessions in parallel, this shows what each one is, what it is doing and since when, tells you which one has finished or is waiting for you, and takes you there in one click.

## Notifications

- **Notifies on:** a finished turn (`Stop`), and a permission prompt or question that needs your answer (`Notification`)
- **Shows:** the session name, plus the start of your last prompt. The name comes from `/rename` if you set one. Otherwise it is the session topic from the Terminal tab title, and if that is missing, the project folder.
- **Click:** brings Terminal.app to the front and selects that session's tab. The tab is matched by tty.
- **One per session:** each session gets its own notification. A newer notification from a session replaces its older one, so they don't pile up.
- **Quiet while background work runs:** a turn that ends while the session still has background tasks running (`run_in_background` commands, monitors) is only a progress update, so it does not notify. You get the notification for the turn after they finish. Set `SESSION_DRAWER_EVERY_TURN=1` to be notified on every turn.
- **Quiet when in front:** if that session's tab is the selected tab of the frontmost Terminal window, nothing is shown, because you are already looking at it.
- **No dependencies:** a small Swift app using the native `UserNotifications` API, with its own entry in System Settings → Notifications. It does not use `terminal-notifier` or `osascript`.

## Menu bar session list

The app also lives in the menu bar and lists your Claude Code sessions. The icon shows how many sessions need you (a bell with a count).

- **Each row:** the session name, its state and how long ago it changed, the folder, your last prompt (`›`) and the first line of Claude's last answer (`⤷`) or the question it is waiting on.
- **States:** ⏳ waiting for you, ✅ done and not looked at yet, ◐ working, ✔︎ done and seen, ✳ ready, ⚪ ended (greyed out, listed for 7 days).
- **Order:** at the top, the sessions active today, plus any session waiting for you or working: waiting first, then unseen finished ones, then the rest by last activity. Older sessions sit in groups by last activity that start collapsed and open in place with a click (*Yesterday*, *Earlier this week*, *Older*), and ended ones under *Closed*. Empty groups are hidden. Using a session again moves it back to the top.
- **Click a row:** brings its Terminal tab to front.
- **Seen:** a finished session counts as seen when you click its row or its notification, when its tab was already in front as it finished, or once you send it a new prompt. The app does not poll Terminal for the front tab.
- **Notifications clean up:** once a session no longer needs you (seen, or answered in Terminal), its notification is removed from the screen and from Notification Center.
- **Several accounts:** sessions run with a different `HOME` (e.g. a second Claude Code account) are tagged with that account's folder name. Point their state folder at the shared one, see *How it works*.
- **No AI involved:** everything comes from hook events and the session transcript.

## Requirements

- macOS 13+ (tested on macOS 15)
- Terminal.app (other terminals: notifications work, click only activates Terminal.app)
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`
- `jq`

## Install

```bash
git clone https://github.com/msziva/session-drawer.git
bash session-drawer/install.sh
```

`install.sh` does four things:

1. builds `~/Applications/SessionDrawer.app` and signs it ad-hoc
2. copies the hook script to `~/.claude/hooks/session-drawer.sh`
3. adds the hooks to `~/.claude/settings.json`: `Stop` and `Notification` notify, while `SessionStart`, `UserPromptSubmit`, `PostToolUse` and `SessionEnd` keep the menu bar list current
4. adds a LaunchAgent (`~/Library/LaunchAgents/io.github.msziva.session-drawer.plist`) that starts the menu bar list at login, and starts it now

It backs up `settings.json` before changing it, keeps your existing hooks, and you can safely run it again.

After that:

1. Restart running Claude Code sessions, or open `/hooks` once in each.
2. **The first notification:** allow notifications for *Session Drawer*.
3. **The first click:** allow *Session Drawer* to control Terminal. Tab switching needs this.

Tip: name your sessions with `/rename <name>`. The name shows in both the tab title and the notification.

### Keep notifications on screen

By default macOS shows notifications as *Banners*, which disappear after about 5 seconds. You can't change that duration. To keep them on screen until you click or dismiss them, open **System Settings → Notifications → Session Drawer** and set the style to **Alerts**.

This works well with session-drawer because each session has at most one notification, so only the sessions that are done or waiting stay on screen. Notifications that have already disappeared are still in Notification Center.

## Uninstall

```bash
bash session-drawer/uninstall.sh
```

## How it works

Every hook event updates a small JSON state file per session in `~/Library/Application Support/SessionDrawer/sessions/`: status, tty, the `claude` process id, session name, last prompt, the start of the last answer and recent events. The `PostToolUse` hook returns right away unless the session was waiting for a permission prompt. The menu bar app rereads these files every 2 seconds, treats a session as ended when its process is gone, and reads the Terminal tab titles when you open the menu. State files older than a week are deleted.

A second Claude Code account that runs with its own `HOME` writes its state files under that `HOME`. Symlink that folder to the main one so both show up in the same list:

```bash
ln -s "$HOME/Library/Application Support/SessionDrawer" "<other HOME>/Library/Application Support/SessionDrawer"
```

For notifications, the hook script reads the hook payload. It takes the session name or folder, the last prompt, and the session id. It then walks up the process tree to find the `claude` process's tty and launches the app with those values. The app posts the notification with the session id as its identifier, so a newer one replaces the older one. It stores the tty in the notification's `userInfo`. On click, macOS relaunches the app with the response. The app then runs a short AppleScript that selects the Terminal tab whose `tty` matches.

## License

MIT
