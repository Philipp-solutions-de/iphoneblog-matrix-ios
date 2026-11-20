//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//
// Where the reader stopped, per room and per thread, Tweetbot-style (Thorsten, 2026-11-19):
// a room or thread opens at the message that was at the top when the reader left it, with
// "Zum Ende springen" to the newest. On this device only, never on the server (Thorsten's rule:
// no personal data there). Element X's timeline table reports the position when scrolling stops
// and when it disappears (one patch); the room and thread screens restore it when they open.

import Foundation

public final class ChatReadPositions: @unchecked Sendable {
    public static let shared: ChatReadPositions = {
        let positions = ChatReadPositions(defaults: .standard)
        // UI and perf tests sign in as the same test accounts again and again. A position one
        // test left in a shared room (Allgemein) opened the next test's room in the middle, away
        // from the messages it looks for (CI, PR #48). Each test starts without; only the
        // read-position tests keep what they saved across their own relaunch. Not behind DEBUG:
        // ChatKit's Perf configuration has none, and only test launches set IPHONEBLOG_DEV_USER.
        let env = ProcessInfo.processInfo.environment
        if env["IPHONEBLOG_DEV_USER"] != nil, env["IPHONEBLOG_KEEP_READPOS"] != "1" {
            positions.removeAll()
        }
        return positions
    }()

    /// About this many rooms and threads are kept; the oldest go first.
    public static let capacity = 500

    private let defaults: UserDefaults
    private let lock = NSLock()
    private static let indexKey = "readpos.index"
    /// Positions being restored: the table puts these at the top of the screen, not the bottom
    /// where Element X puts a permalink.
    private var restoring: Set<String> = []
    /// Restored positions show no highlight, ever (Thorsten: "what does the green mean?").
    private var quiet: Set<String> = []
    /// Per room, the main-timeline events the reader's receipts named since the room opened.
    private var seen: [String: [String]] = [:]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func key(user: String, room: String, thread: String?) -> String {
        "readpos.\(user).\(room).\(thread ?? "main")"
    }

    /// The event at the top of the screen when the reader last left, if not at the newest.
    public func position(user: String, room: String, thread: String?) -> String? {
        (defaults.dictionary(forKey: Self.key(user: user, room: room, thread: thread)))?["event"] as? String
    }

    /// Records where the reader is; nil (at the newest message) clears it.
    public func record(_ eventID: String?, user: String, room: String, thread: String?) {
        let key = Self.key(user: user, room: room, thread: thread)
        lock.lock()
        defer { lock.unlock() }
        var index = defaults.dictionary(forKey: Self.indexKey) as? [String: Double] ?? [:]
        guard let eventID else {
            defaults.removeObject(forKey: key)
            index[key] = nil
            defaults.set(index, forKey: Self.indexKey)
            return
        }
        let now = Date().timeIntervalSince1970
        defaults.set(["event": eventID, "at": now], forKey: key)
        index[key] = now
        if index.count > Self.capacity {
            for (old, _) in index.sorted(by: { $0.value < $1.value }).prefix(index.count - Self.capacity) {
                defaults.removeObject(forKey: old)
                index[old] = nil
            }
        }
        defaults.set(index, forKey: Self.indexKey)
    }

    /// Forgets every saved position.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        let index = defaults.dictionary(forKey: Self.indexKey) as? [String: Double] ?? [:]
        for key in index.keys { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: Self.indexKey)
    }

    /// The saved position for a screen about to open, marked for restoring.
    func restore(user: String, room: String, thread: String?) -> String? {
        guard let eventID = position(user: user, room: room, thread: thread) else { return nil }
        lock.lock()
        restoring.insert(eventID)
        quiet.insert(eventID)
        lock.unlock()
        return eventID
    }

    /// Whether this focused event is a restored read position, which gets no highlight.
    func isQuiet(_ eventID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return quiet.contains(eventID)
    }

    /// A read receipt went out for this event (Element X's TimelineController).
    func noteSeen(room: String, thread: String?, event: String) {
        guard thread == nil else { return }
        lock.lock()
        defer { lock.unlock() }
        seen[room, default: []].append(event)
    }

    /// The events seen in the room since the last call.
    func takeSeen(room: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return seen.removeValue(forKey: room) ?? []
    }

    func isRestoring(_ eventID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return restoring.contains(eventID)
    }

    /// The table scrolled to a restored position; from now on the event is an ordinary one.
    func didRestore(_ eventID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return restoring.remove(eventID) != nil
    }
}
