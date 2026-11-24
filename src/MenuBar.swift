// Menu bar list of Claude Code sessions: what each one is, what it is doing, since when.
// Clicking a session brings its Terminal tab to front.
import AppKit
import UserNotifications

final class MenuBarController: NSObject, NSMenuDelegate {
    private let store = SessionStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var watcher: TerminalWatcher?
    private let search = SearchFieldView()
    /// Separator above "Quit": session rows go between the search field and this.
    private var footer: NSMenuItem?
    private var tabTitles: [String: String] = [:]
    /// Sessions matching the current search, in list order.
    private var matches: [Session] = []
    /// The app that was active when the menu opened, and whether a session was opened from it.
    private var previousApp: NSRunningApplication?
    private var openedSession = false
    /// Sessions that needed you at the last update, to spot the ones that no longer do.
    private var attentionIDs: Set<String> = []
    /// Whether the status item got its fixed width yet.
    private var lengthFixed = false

    override init() {
        super.init()
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        search.onChange = { [weak self] query in self?.fill(query: query) }
        search.onSubmit = { [weak self] in self?.openFirstMatch() }
        search.onCancel = { [weak self] in self?.menu.cancelTracking() }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Switching to a finished session's tab yourself also counts as seeing it.
        watcher = TerminalWatcher(
            isWanted: { [weak self] in
                guard let store = self?.store else { return false }
                return store.sessions.contains { $0.status == "done" && store.needsAttention($0) }
            },
            onFrontTab: { [weak self] tty in self?.markSeen(tty: tty) })
    }

    func markSeen(tty: String) {
        store.reload()
        for session in store.sessions where session.tty == tty {
            store.markSeen(session)
        }
        updateButton()
    }

    /// For a session without a tab (Claude Desktop): many share the empty tty.
    func markSeen(sessionId: String) {
        store.reload()
        for session in store.sessions where session.sessionId == sessionId {
            store.markSeen(session)
        }
        updateButton()
    }

    /// Brings a session to front and counts it as seen.
    private func openSession(_ session: Session) {
        openedSession = true
        session.focus()
        if let tty = session.tty, !tty.isEmpty {
            markSeen(tty: tty)
        } else {
            markSeen(sessionId: session.sessionId)
        }
    }

    private func refresh() {
        store.reload()
        updateButton()
    }

    private func updateButton() {
        dismissHandledNotifications()
        guard let button = statusItem.button else { return }
        let count = store.attentionCount
        let description = "Claude sessions"
        if !lengthFixed {
            // Keep the natural width of the idle icon for good: a status item that changes
            // width moves every icon to its left.
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: description)
            if button.frame.width > 0 {
                statusItem.length = button.frame.width
                lengthFixed = true
            }
        }
        let terminal = NSImage(systemSymbolName: "terminal", accessibilityDescription: description)
        // The count goes inside the icon, so it takes no extra room.
        button.image = count == 0 ? terminal : countImage(count, size: terminal?.size ?? NSSize(width: 19, height: 14))
        button.image?.isTemplate = true
    }

    /// The terminal icon with the count in it in place of the prompt.
    private func countImage(_ count: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            // The screen of the "terminal" symbol.
            let screen = NSRect(x: bounds.midX - 7.75, y: bounds.midY - 6, width: 15.5, height: 12)
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: screen.insetBy(dx: 0.625, dy: 0.625), xRadius: 1.5, yRadius: 1.5)
            outline.lineWidth = 1.25
            outline.stroke()
            let text = String(min(count, 99))
            let font = NSFont.systemFont(ofSize: text.count > 1 ? 8.5 : 9.5, weight: .bold)
            let string = NSAttributedString(string: text, attributes: [.font: font])
            let textSize = string.size()
            string.draw(at: NSPoint(x: bounds.midX - textSize.width / 2,
                                    y: bounds.midY - textSize.height / 2))
            return true
        }
        image.accessibilityDescription = "Claude sessions"
        return image
    }

    /// Removes the notification of a session once it no longer needs you: you opened it from
    /// the list or the notification, or answered it in Terminal.
    private func dismissHandledNotifications() {
        let current = Set(store.sessions.filter(store.needsAttention).map(\.sessionId))
        let handled = attentionIDs.subtracting(current)
        let added = current.subtracting(attentionIDs)
        attentionIDs = current
        if !handled.isEmpty {
            removeNotifications(of: handled)
            // The hook posts the notification a moment after it writes the state: one handled
            // this fast may not be delivered yet, so remove it once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                removeNotifications(of: handled.subtracting(attentionIDs))
            }
        }
        // A session that finished just now may already have its tab in front: the tab switch
        // came before this list knew there was something to mark.
        if !added.isEmpty { watcher?.scheduleCheck(force: true) }
    }

    private func removeNotifications(of sessionIDs: Set<String>) {
        guard !sessionIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: sessionIDs.map { "session-" + $0 })
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.reload()
        updateButton()
        menu.removeAllItems()
        tabTitles = Terminal.tabTitles()

        let searchItem = NSMenuItem()
        searchItem.view = search
        search.clear()
        menu.addItem(searchItem)

        footer = NSMenuItem.separator()
        menu.addItem(footer!)
        menu.addItem(NSMenuItem(title: "Quit Session Drawer",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        fill(query: "")

        // Size the menu for every session row, collapsed or filtered out, so opening a group or
        // searching does not widen it (a wider menu gets moved left on screen).
        let widest = store.sessions.compactMap { item(for: $0).attributedTitle?.size().width }.max() ?? 0
        menu.minimumWidth = max(widest + 40, 300)
    }

    /// A text field in a menu only takes typing while its app is active, but a menu bar menu
    /// opens without activating it, and activating while it is open closes it. So activate
    /// first and open the menu once that is done. The app that was active gets the focus back.
    @objc private func statusItemClicked() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        if NSApp.isActive { showMenu(); return }
        var shown = false
        var observer: NSObjectProtocol?
        let show = { [weak self] in
            guard !shown else { return }
            shown = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            self?.showMenu()
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in show() }
        NSApp.activate(ignoringOtherApps: true)
        // Open it anyway if the activation does not come through.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { show() }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        openedSession = false
        // The menu runs its own event loop while open; focus the field from inside it.
        RunLoop.main.perform(inModes: [.eventTracking, .default]) { [search] in
            search.focus()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // The chosen row's action runs after this; let it go first.
        DispatchQueue.main.async { [self] in
            guard !openedSession, let previousApp else { return }
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: previousApp) }
            previousApp.activate()
        }
    }

    /// Replaces the rows between the search field and the footer: the grouped list when the
    /// query is empty, otherwise every session that matches it.
    private func fill(query: String) {
        guard let footer else { return }
        while menu.items.count > 1, menu.items[1] !== footer { menu.removeItem(at: 1) }
        var rows: [NSMenuItem] = []
        let words = normalize(query).split(separator: " ").map(String.init)

        if !words.isEmpty {
            matches = store.sessions.filter { session in
                let text = normalize(searchText(session))
                return words.allSatisfy { text.contains($0) }
            }
            rows = matches.map(item(for:))
            if rows.isEmpty { rows = [disabled("No matching sessions")] }
        } else {
            matches = []
            let groups = group(store.sessions)
            rows = groups.current.isEmpty ? [disabled("No active sessions today")] : groups.current.map(item(for:))

            // Earlier sessions sit in groups that start collapsed and open in place;
            // using a session again moves it back to the top.
            let collapsed = groups.collapsed.filter { !$0.sessions.isEmpty }
            if !collapsed.isEmpty { rows.append(.separator()) }
            for (title, sessions) in collapsed {
                let header = NSMenuItem()
                let view = GroupHeaderView(title: title, count: sessions.count)
                header.view = view
                rows.append(header)
                let items = sessions.map(item(for:))
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
        }
        for (offset, row) in rows.enumerated() { menu.insertItem(row, at: 1 + offset) }
    }

    /// Opens the first match (Return in the search field).
    private func openFirstMatch() {
        guard let session = matches.first(where: { !$0.isEnded }) else { return }
        menu.cancelTracking()
        openSession(session)
    }

    private func searchText(_ session: Session) -> String {
        [session.label, tabTitle(session), session.cwd, session.account,
         session.lastPrompt, session.lastAnswer, session.message]
            .compactMap { $0 }.joined(separator: " ")
    }

    /// Case and accent insensitive, so "fozes" finds "Főzés".
    private func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func tabTitle(_ session: Session) -> String? {
        session.tty.flatMap { tabTitles[$0] }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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

    private func item(for session: Session) -> NSMenuItem {
        let tabTitle = tabTitle(session)
        let item = NSMenuItem(title: "", action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session.sessionId
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
        let id = sender.representedObject as? String ?? ""
        guard let session = store.sessions.first(where: { $0.sessionId == id }) else { return }
        openSession(session)
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

/// Search field at the top of the menu. Typing filters the session rows, Return opens the first
/// match, Escape clears the field (or closes the menu when it is empty).
final class SearchFieldView: NSView, NSSearchFieldDelegate {
    var onChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    private let field = NSSearchField()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        autoresizingMask = [.width]
        field.frame = NSRect(x: 12, y: 5, width: 276, height: 22)
        field.autoresizingMask = [.width]
        field.placeholderString = "Search sessions"
        field.sendsSearchStringImmediately = true
        field.delegate = self
        // The clear (x) button only sends the action, not a text change.
        field.target = self
        field.action = #selector(searchChanged)
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func clear() { field.stringValue = "" }

    func focus() { window?.makeFirstResponder(field) }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }

    @objc private func searchChanged() {
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onSubmit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty {
                onCancel?()
            } else {
                clear()
                onChange?("")
            }
            return true
        default:
            return false
        }
    }
}
