// Claude Desktop access: opening a Claude Code session of its Code tab through its deep link.
import AppKit

enum ClaudeDesktop {
    static let bundleID = "com.anthropic.claudefordesktop"

    /// Where the app keeps one metadata file per Code session: <account>/<org>/local_<uuid>.json.
    static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")

    /// Shows the session in Claude Desktop. Returns false when the app does not know it.
    @discardableResult
    static func focusSession(cliSessionId: String) -> Bool {
        guard let id = desktopSessionId(cliSessionId: cliSessionId),
              let url = URL(string: "claude://code/continue?session=\(id)") else { return false }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        NSWorkspace.shared.open(url)
        return true
    }

    static func activate() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The app's own id for a Claude Code session id. The deep link only takes this one.
    /// Sessions started in the app get a new uuid; terminal sessions it lists keep theirs.
    private static func desktopSessionId(cliSessionId: String) -> String? {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        var files: [URL] = []
        for account in (try? fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? [] {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                files += ((try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            }
        }
        // A terminal session's file is named after it: try that one first.
        let sameName = "local_\(cliSessionId).json"
        let first = files.filter { $0.lastPathComponent == sameName }
        for file in first + files.filter({ $0.lastPathComponent != sameName }) {
            guard let data = try? Data(contentsOf: file),
                  let meta = try? decoder.decode(Meta.self, from: data),
                  meta.cliSessionId == cliSessionId || meta.lastAssistantCliSessionId == cliSessionId
            else { continue }
            return meta.sessionId
        }
        return nil
    }

    private struct Meta: Decodable {
        let sessionId: String
        let cliSessionId: String?
        let lastAssistantCliSessionId: String?
    }
}
