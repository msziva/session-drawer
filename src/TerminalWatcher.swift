// Notices when you bring a Terminal tab to front yourself, without polling: Terminal reports
// focus and window title changes through the Accessibility API, and switching tabs changes the
// window title. Without the Accessibility permission it still reacts to Terminal activation.
import AppKit
import ApplicationServices

final class TerminalWatcher {
    /// Whether a front-tab check could change anything (e.g. a finished session is unseen).
    private let isWanted: () -> Bool
    private let onFrontTab: (String) -> Void
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var focusedWindow: AXUIElement?
    private var checkScheduled = false
    /// Front window title at the last check. Title changes that keep it (Claude Code animating
    /// the status glyph while working) are skipped.
    private var lastTitleKey: String?

    init(isWanted: @escaping () -> Bool, onFrontTab: @escaping (String) -> Void) {
        self.isWanted = isWanted
        self.onFrontTab = onFrontTab
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Terminal.bundleID else { return }
            attach(to: app.processIdentifier)
            scheduleCheck(force: true)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Terminal.bundleID).first {
            attach(to: app.processIdentifier)
        }
    }

    /// Starts observing Terminal's process (again, if it was relaunched or the permission came later).
    private func attach(to pid: pid_t) {
        guard observer == nil || pid != observedPID, AXIsProcessTrusted() else { return }
        if let old = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
        }
        observer = nil
        focusedWindow = nil
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<TerminalWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(notification as String)
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
        watchFocusedWindow()
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func handle(_ notification: String) {
        if notification == kAXTitleChangedNotification {
            scheduleCheck(force: false)
        } else {
            watchFocusedWindow()
            scheduleCheck(force: true)
        }
    }

    /// Title changes are reported per window, so follow the focused one.
    private func watchFocusedWindow() {
        guard let observer else { return }
        if let old = focusedWindow {
            AXObserverRemoveNotification(observer, old, kAXTitleChangedNotification as CFString)
        }
        focusedWindow = frontWindow()
        if let window = focusedWindow {
            AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, refcon)
        }
    }

    private func frontWindow() -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(observedPID)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func frontTitleKey() -> String? {
        guard let window = focusedWindow else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String else { return nil }
        return String(title.unicodeScalars.filter { !CharacterSet.symbols.contains($0) }.map(Character.init))
    }

    /// Coalesces bursts of events into one check shortly after they settle.
    private func scheduleCheck(force: Bool) {
        if force { lastTitleKey = nil }
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            checkScheduled = false
            guard Terminal.isFrontmost, isWanted() else { return }
            let key = frontTitleKey()
            if let key, key == lastTitleKey { return }
            lastTitleKey = key
            if let tty = Terminal.frontTTY() { onFrontTab(tty) }
        }
    }
}
