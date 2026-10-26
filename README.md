# term-tab-notify

macOS notifications for [Claude Code](https://claude.com/claude-code) sessions running in **Terminal.app**. Click a notification and it switches to the exact tab that sent it.

When you run several Claude Code sessions in parallel, this tells you which one has finished or is waiting for you, and takes you there in one click.

- **Notifies on:** a finished turn (`Stop`), and a permission prompt or question that needs your answer (`Notification`)
- **Shows:** the session name, plus the start of your last prompt. The name comes from `/rename` if you set one. Otherwise it is the session topic from the Terminal tab title, and if that is missing, the project folder.
- **Click:** brings Terminal.app to the front and selects that session's tab. The tab is matched by tty.
- **One per session:** each session gets its own notification. A newer notification from a session replaces its older one, so they don't pile up.
- **Quiet when in front:** if that session's tab is the selected tab of the frontmost Terminal window, nothing is shown, because you are already looking at it.
- **No dependencies:** a ~100-line Swift app using the native `UserNotifications` API, with its own entry in System Settings → Notifications. It does not use `terminal-notifier` or `osascript`.

## Requirements

- macOS 13+ (tested on macOS 15)
- Terminal.app (other terminals: notifications work, click only activates Terminal.app)
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`
- `jq`

## Install

```bash
git clone https://github.com/msziva/term-tab-notify.git
bash term-tab-notify/install.sh
```

`install.sh` does three things:

1. builds `~/Applications/TermTabNotify.app` and signs it ad-hoc
2. copies the hook script to `~/.claude/hooks/term-tab-notify.sh`
3. adds the `Stop` and `Notification` hooks to `~/.claude/settings.json`

It backs up `settings.json` before changing it, keeps your existing hooks, and you can safely run it again.

After that:

1. Restart running Claude Code sessions, or open `/hooks` once in each.
2. **The first notification:** allow notifications for *Term Tab Notify*. Set the style to *Alerts* in System Settings if you want notifications to stay until clicked.
3. **The first click:** allow *Term Tab Notify* to control Terminal. Tab switching needs this.

Tip: name your sessions with `/rename <name>`. The name shows in both the tab title and the notification.

## Uninstall

```bash
bash term-tab-notify/uninstall.sh
```

## How it works

The hook script reads the hook payload. It takes the session name or folder, the last prompt, and the session id. It then walks up the process tree to find the `claude` process's tty and launches the app with those values. The app posts the notification with the session id as its identifier, so a newer one replaces the older one. It stores the tty in the notification's `userInfo`. On click, macOS relaunches the app with the response. The app then runs a short AppleScript that selects the Terminal tab whose `tty` matches.

## License

MIT
