// term-tab-notify: posts a macOS notification for a Claude Code session and, when the
// notification is clicked, brings the Terminal.app tab with the session's tty to front.
//
// Usage: TermTabNotify --title T --body B --id SESSION_ID --tty /dev/ttysNNN
// Launched without arguments (e.g. by a notification click) it only handles the click.
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        center.delegate = self
        let args = parseArgs()
        guard let title = args["title"] else {
            // Click-launch: the delegate callback arrives shortly; quit if nothing comes.
            quit(after: 5)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { self.quit(after: 0); return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = args["body"] ?? ""
            content.userInfo = ["tty": args["tty"] ?? ""]
            // Same identifier per session: a newer notification replaces the older one.
            let request = UNNotificationRequest(
                identifier: "session-" + (args["id"] ?? UUID().uuidString),
                content: content,
                trigger: nil)
            self.center.add(request) { _ in self.quit(after: 0.5) }
        }
    }

    // Show banners even if this app happens to be frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let tty = response.notification.request.content.userInfo["tty"] as? String ?? ""
        focusTerminalTab(tty: tty)
        completionHandler()
        quit(after: 0.5)
    }

    func focusTerminalTab(tty: String) {
        let source: String
        if tty.isEmpty {
            source = "tell application \"Terminal\" to activate"
        } else {
            source = """
            tell application "Terminal"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    func parseArgs() -> [String: String] {
        var result: [String: String] = [:]
        let argv = CommandLine.arguments
        var i = 1
        while i < argv.count - 1 {
            if argv[i].hasPrefix("--") {
                result[String(argv[i].dropFirst(2))] = argv[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return result
    }

    func quit(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
