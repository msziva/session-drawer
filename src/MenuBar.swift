// Menu bar list of Claude Code sessions: what each one is, what it is doing, since when.
// Clicking a session brings its Terminal tab to front.
import AppKit
import UserNotifications

final class MenuBarController: NSObject, NSMenuDelegate {
    private let store = SessionStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    /// Sessions that needed you at the last update, to spot the ones that no longer do.
    private var attentionIDs: Set<String> = []

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func markSeen(tty: String) {
        store.reload()
        for session in store.sessions where session.tty == tty {
            store.markSeen(session)
        }
        updateButton()
    }

    private func refresh() {
        store.reload()
        updateButton()
    }

    private func updateButton() {
        dismissHandledNotifications()
        guard let button = statusItem.button else { return }
        let count = store.attentionCount
        let symbol = count > 0 ? "bell.badge.fill" : "terminal"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude sessions")
        button.image?.isTemplate = true
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = .imageLeading
    }

    /// Removes the notification of a session once it no longer needs you: you opened it from
    /// the list or the notification, or answered it in Terminal.
    private func dismissHandledNotifications() {
        let current = Set(store.sessions.filter(store.needsAttention).map(\.sessionId))
        let handled = attentionIDs.subtracting(current)
        if !handled.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: handled.map { "session-" + $0 })
        }
        attentionIDs = current
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.reload()
        updateButton()
        menu.removeAllItems()

        let header = NSMenuItem(title: "Claude Code sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let titles = Terminal.tabTitles()
        let groups = group(store.sessions)

        if groups.current.isEmpty {
            let empty = NSMenuItem(title: "No active sessions today", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for session in groups.current {
            menu.addItem(item(for: session, tabTitle: session.tty.flatMap { titles[$0] }))
        }

        // Earlier sessions sit in groups that start collapsed and open in place;
        // using a session again moves it back to the top.
        let collapsed = groups.collapsed.filter { !$0.sessions.isEmpty }
        var hiddenItems: [NSMenuItem] = []
        if !collapsed.isEmpty { menu.addItem(.separator()) }
        for (title, sessions) in collapsed {
            let header = NSMenuItem()
            let view = GroupHeaderView(title: title, count: sessions.count)
            header.view = view
            menu.addItem(header)
            let items = sessions.map { item(for: $0, tabTitle: $0.tty.flatMap { titles[$0] }) }
            hiddenItems += items
            view.onToggle = { [unowned view, weak menu, weak header] in
                guard let menu, let header else { return }
                if view.isExpanded {
                    for (offset, item) in items.enumerated() {
                        menu.insertItem(item, at: menu.index(of: header) + 1 + offset)
                    }
                } else {
                    for item in items where item.menu != nil { menu.removeItem(item) }
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Session Drawer",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Size the menu for the collapsed rows too, so opening a group does not widen it
        // (a wider menu gets moved left on screen).
        let widest = (menu.items + hiddenItems).compactMap { $0.attributedTitle?.size().width }.max() ?? 0
        menu.minimumWidth = widest + 40
    }

    /// Top of the menu: active today, waiting for you or working, however old.
    /// The rest goes into calendar groups by last activity (weeks start on Monday), and
    /// closed sessions into their own group.
    private func group(_ sessions: [Session]) -> (current: [Session], collapsed: [(title: String, sessions: [Session])]) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let now = Date()
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterday = today - 86400
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start.timeIntervalSince1970 ?? yesterday

        var current: [Session] = []
        var (yesterdays, thisWeek, older, closed) = ([Session](), [Session](), [Session](), [Session]())
        for session in sessions {
            if session.isEnded {
                closed.append(session)
            } else if store.needsAttention(session) || session.status == "working" || session.updatedAt >= today {
                current.append(session)
            } else if session.updatedAt >= yesterday {
                yesterdays.append(session)
            } else if session.updatedAt >= week {
                thisWeek.append(session)
            } else {
                older.append(session)
            }
        }
        return (current, [("Yesterday", yesterdays), ("Earlier this week", thisWeek),
                          ("Older", older), ("Closed", closed)])
    }

    private func item(for session: Session, tabTitle: String?) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session.tty ?? ""
        item.isEnabled = !session.isEnded

        let name = session.label ?? tabTitle ?? session.folder
        let (icon, state) = describe(session)

        let text = NSMutableAttributedString()
        let titleFont = NSFont.menuFont(ofSize: 0)
        let detailFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let primary: NSColor = session.isEnded ? .tertiaryLabelColor : .labelColor
        let secondary: NSColor = session.isEnded ? .tertiaryLabelColor : .secondaryLabelColor

        text.append(NSAttributedString(string: "\(icon)  \(truncate(name, 60))", attributes: [
            .font: NSFont.boldSystemFont(ofSize: titleFont.pointSize), .foregroundColor: primary]))
        var meta = "   \(state) · \(ago(session.updatedAt))"
        if session.label != nil || tabTitle != nil { meta += " · \(truncateMiddle(session.folder, 24))" }
        if let account = session.account { meta += " · \(account)" }
        text.append(NSAttributedString(string: meta, attributes: [
            .font: detailFont, .foregroundColor: secondary]))

        var details: [String] = []
        if let prompt = session.lastPrompt, !prompt.isEmpty {
            details.append("› " + truncate(prompt, 90))
        }
        if session.status == "waiting", let message = session.message {
            details.append("⏳ " + truncate(message, 90))
        } else if let answer = session.lastAnswer, !answer.isEmpty {
            details.append("⤷ " + truncate(answer, 90))
        }
        for line in details {
            text.append(NSAttributedString(string: "\n      " + line, attributes: [
                .font: detailFont, .foregroundColor: secondary]))
        }

        item.attributedTitle = text
        if let started = session.startedAt {
            item.toolTip = "Started \(ago(started)) ago · \(session.cwd ?? "")"
        }
        return item
    }

    private func describe(_ session: Session) -> (String, String) {
        if session.isEnded { return ("⚪", "ended") }
        switch session.status {
        case "waiting": return ("⏳", "waiting for you")
        case "working": return ("◐", "working")
        case "done": return store.isSeen(session) ? ("✔︎", "done") : ("✅", "done")
        default: return ("✳", "ready")
        }
    }

    @objc private func open(_ sender: NSMenuItem) {
        let tty = sender.representedObject as? String ?? ""
        Terminal.focusTab(tty: tty)
        markSeen(tty: tty)
    }

    private func ago(_ timestamp: Double) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince1970 - timestamp))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }

    private func truncate(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    /// "drive-download-20261027T193805Z-1-001" -> "drive-download…5Z-1-001"
    private func truncateMiddle(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        let tail = (limit - 1) / 3
        return String(text.prefix(limit - 1 - tail)) + "…" + String(text.suffix(tail))
    }
}

/// Group header inside the menu: clicking it opens or closes the group in place,
/// without closing the menu.
final class GroupHeaderView: NSView {
    var onToggle: (() -> Void)?
    private(set) var isExpanded = false
    private let title: String
    private let count: Int
    private let label = NSTextField(labelWithString: "")

    init(title: String, count: Int) {
        self.title = title
        self.count = count
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        autoresizingMask = [.width]
        label.font = NSFont.menuFont(ofSize: 0)
        label.frame = NSRect(x: 14, y: 3, width: 256, height: 16)
        label.autoresizingMask = [.width]
        addSubview(label)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        label.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
    }

    override func mouseUp(with event: NSEvent) {
        isExpanded.toggle()
        updateLabel()
        onToggle?()
    }

    private func updateLabel() {
        label.stringValue = "\(isExpanded ? "▾" : "▸")  \(title)  (\(count))"
    }
}
