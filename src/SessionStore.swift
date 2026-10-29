// Reads the per-session state files written by the hook script.
import Foundation

struct Session: Decodable {
    let sessionId: String
    let home: String?
    let cwd: String?
    let transcript: String?
    let tty: String?
    let pid: Int32?
    let startedAt: Double?
    let updatedAt: Double
    let status: String
    /// /rename name: from the hook, replaced by the transcript's newest one by the store.
    var label: String?
    let lastPrompt: String?
    let lastAnswer: String?
    let message: String?
    let seen: Bool?

    /// Set by the store: the claude process is gone or SessionEnd arrived.
    var isEnded = false

    enum CodingKeys: String, CodingKey {
        case sessionId, home, cwd, transcript, tty, pid, startedAt, updatedAt, status
        case label, lastPrompt, lastAnswer, message, seen
    }

    var folder: String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return (cwd as NSString).lastPathComponent
    }

    /// Name of the Claude Code account when it runs with a different HOME
    /// (e.g. "claude-second" for HOME=~/.claude-second), nil for the default one.
    var account: String? {
        guard let home, !home.isEmpty, home != NSHomeDirectory() else { return nil }
        let name = (home as NSString).lastPathComponent
        return name.hasPrefix(".") ? String(name.dropFirst()) : name
    }
}

final class SessionStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SessionDrawer/sessions")

    /// Ended sessions stay listed this long; state files are deleted after `keepFiles`.
    let showEnded: TimeInterval = 7 * 24 * 3600
    let keepFiles: TimeInterval = 7 * 24 * 3600

    private let seenKey = "seenSessions"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private(set) var sessions: [Session] = []

    func reload() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil)) ?? []

        var loaded: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  var session = try? decoder.decode(Session.self, from: data) else { continue }
            if now - session.updatedAt > keepFiles {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            session.isEnded = session.status == "ended" || !isAlive(session.pid)
            if !session.isEnded, let title = renamedTitle(transcript: session.transcript) {
                session.label = title
            }
            loaded.append(session)
        }

        // /clear starts a new session id in the same process: only the newest one per live tab counts.
        var newestPerTTY: [String: Double] = [:]
        for session in loaded where !session.isEnded {
            if let tty = session.tty, !tty.isEmpty {
                newestPerTTY[tty] = max(newestPerTTY[tty] ?? 0, session.updatedAt)
            }
        }
        sessions = loaded.filter { session in
            if session.isEnded { return now - session.updatedAt < showEnded }
            guard let tty = session.tty, let newest = newestPerTTY[tty] else { return true }
            return session.updatedAt >= newest
        }
        .sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            return ra != rb ? ra < rb : a.updatedAt > b.updatedAt
        }
    }

    /// Waiting for you, or finished while you were looking elsewhere.
    func needsAttention(_ session: Session) -> Bool {
        guard !session.isEnded else { return false }
        return session.status == "waiting" || (session.status == "done" && !isSeen(session))
    }

    var attentionCount: Int { sessions.filter(needsAttention).count }

    func isSeen(_ session: Session) -> Bool {
        if session.seen == true { return true }
        let seen = UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Double] ?? [:]
        return seen[session.sessionId] == session.updatedAt
    }

    func markSeen(_ session: Session) {
        var seen = UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Double] ?? [:]
        seen[session.sessionId] = session.updatedAt
        let live = Set(sessions.map(\.sessionId))
        seen = seen.filter { live.contains($0.key) }
        UserDefaults.standard.set(seen, forKey: seenKey)
    }

    private func rank(_ session: Session) -> Int {
        if session.isEnded { return 4 }
        switch session.status {
        case "waiting": return 0
        case "done": return isSeen(session) ? 3 : 1
        case "working": return 2
        default: return 3
        }
    }

    /// Newest /rename name in a transcript. /rename runs no hook, so the state file only learns
    /// it at the next event; the transcript has it at once. Reads only what was appended since
    /// the last call.
    private var titleCache: [String: (offset: UInt64, title: String?)] = [:]
    private let titleMarker = Data("\"custom-title\"".utf8)

    private func renamedTitle(transcript path: String?) -> String? {
        guard let path, !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var cached = titleCache[path] ?? (offset: 0, title: nil)
        if size < cached.offset { cached = (offset: 0, title: nil) }  // rewritten
        guard size > cached.offset else { return cached.title }

        try? handle.seek(toOffset: cached.offset)
        let data = handle.readDataToEndOfFile()
        // Only complete lines: a line still being written is read next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return cached.title }
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: UInt8(ascii: "\n"))
        where line.range(of: titleMarker) != nil {
            if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let title = object["customTitle"] as? String, !title.isEmpty {
                cached.title = title
            }
        }
        cached.offset += UInt64(complete.count)
        titleCache[path] = cached
        return cached.title
    }

    private func isAlive(_ pid: Int32?) -> Bool {
        guard let pid, pid > 1 else { return true }  // unknown: trust the status
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
