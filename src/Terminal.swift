// Terminal.app access through AppleScript: focusing a tab by tty and reading tab titles.
import AppKit

enum Terminal {
    static let bundleID = "com.apple.Terminal"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Brings Terminal.app to front with the tab whose tty matches selected.
    static func focusTab(tty: String) {
        raise(tty: tty)
        activate()
        // Activation can bring back the window that was key before, undoing the raise above
        // (seen with windows on several displays), and a notification click also activates this
        // app, which can take the focus back. Redo both once things have settled.
        for delay in [0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !isFrontmost { activate() }
                if !tty.isEmpty, frontTTY() != tty { raise(tty: tty) }
            }
        }
    }

    /// Selects the tab with this tty and makes its window Terminal's front window.
    private static func raise(tty: String) {
        guard !tty.isEmpty else { return }
        // `w` is a positional reference ("window 3"): once the window moves to the front it points
        // at another window, so take the window by its id first.
        run("""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set target to window id (id of w)
                        set selected of t to true
                        set index of target to 1
                        try
                            set frontmost of target to true
                        end try
                        return
                    end if
                end repeat
            end repeat
        end tell
        """)
    }

    /// tty of the selected tab in Terminal's front window.
    static func frontTTY() -> String? {
        guard isRunning else { return nil }
        let tty = run("tell application \"Terminal\" to return tty of selected tab of front window")
        return tty?.isEmpty == false ? tty : nil
    }

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Since macOS 14 activation is cooperative: the active app (this one, after a notification
    /// click) has to yield, or Terminal's own activation can be refused.
    private static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        run("tell application \"Terminal\" to activate")
    }

    /// Title of every open tab, keyed by tty, with Claude Code's leading status glyph removed.
    /// Empty when Terminal is not running (asking would launch it).
    static func tabTitles() -> [String: String] {
        guard isRunning else { return [:] }
        // `tab` names a Terminal class inside the tell block, so take the separator outside it.
        let output = run("""
        set sep to tab
        set out to ""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & (tty of t) & sep & (custom title of t) & linefeed
                    end try
                end repeat
            end repeat
        end tell
        return out
        """) ?? ""
        var titles: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let title = stripStatusGlyph(parts[1])
            if !title.isEmpty && title != "Terminal" && title != "Claude Code" {
                titles[parts[0]] = title
            }
        }
        return titles
    }

    /// "✳ Fix login bug" -> "Fix login bug"
    static func stripStatusGlyph(_ title: String) -> String {
        var scalars = Substring(title).unicodeScalars
        while let first = scalars.first,
              !CharacterSet.alphanumerics.contains(first) {
            scalars.removeFirst()
        }
        let stripped = String(String.UnicodeScalarView(scalars))
        return stripped.isEmpty ? title.trimmingCharacters(in: .whitespaces) : stripped
    }

    @discardableResult
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}
