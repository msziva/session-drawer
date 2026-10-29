// Terminal.app access through AppleScript: focusing a tab by tty and reading tab titles.
import AppKit

enum Terminal {
    static let bundleID = "com.apple.Terminal"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Brings Terminal.app to front with the tab whose tty matches selected.
    static func focusTab(tty: String) {
        if !tty.isEmpty {
            run("""
            tell application "Terminal"
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
            """)
        }
        activate()
        // A notification click also activates this app, and that can land after the line above
        // and take the focus back. Check once more when it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !isFrontmost { activate() }
        }
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
