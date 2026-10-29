// session-drawer: notifications and a menu bar session list for Claude Code sessions in
// Terminal.app. Clicking a notification or a listed session brings its tab to front.
//
// Usage: SessionDrawer --title T --body B --id SESSION_ID --tty /dev/ttysNNN
//   posts one notification and quits (this is what the hook runs).
// Launched without arguments (at login, or by a notification click) it stays in the menu bar.
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        center.delegate = self
        let args = parseArgs()
        guard let title = args["title"] else {
            NSApp.setActivationPolicy(.accessory)
            menuBar = MenuBarController()
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
        DispatchQueue.main.async {
            Terminal.focusTab(tty: tty)
            self.menuBar?.markSeen(tty: tty)
        }
        completionHandler()
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
