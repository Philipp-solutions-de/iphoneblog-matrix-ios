//
// Copyright 2026 Philipp Solutions. SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os

/// Times a room's opening, step by step, in the log (category "open") and as signposts for
/// Instruments: from the tap to the room's proxy, the screen, the first timeline items and each
/// back-pagination. One open at a time: the newest begin wins.
public enum ChatOpenTrace {
    private static let log = Logger(subsystem: "de.iphoneblog.chat", category: "open")
    private static let signposter = OSSignposter(subsystem: "de.iphoneblog.chat", category: "open")
    nonisolated(unsafe) private static var start: ContinuousClock.Instant?
    nonisolated(unsafe) private static var label = ""
    nonisolated(unsafe) private static var interval: OSSignpostIntervalState?
    private static let lock = NSLock()

    public static func begin(_ what: String) {
        lock.withLock {
            if let interval { signposter.endInterval("open", interval) }
            start = .now
            label = what
            interval = signposter.beginInterval("open", id: signposter.makeSignpostID(), "\(what, privacy: .public)")
        }
        log.notice("open \(what, privacy: .public): begin")
    }

    /// Called once, the first time a timeline shows at least `firstItems` items: the app's
    /// measure of "launch to the first messages" (StartTrace, testOneChatAfterLaunch).
    nonisolated(unsafe) public static var onFirstMessages: (() -> Void)?
    nonisolated(unsafe) private static var firstReported = false
    private static let firstItems = 5

    /// A timeline was built with this many items.
    public static func items(_ count: Int) {
        mark("items \(count)")
        let first = lock.withLock { () -> Bool in
            guard count >= firstItems, !firstReported else { return false }
            firstReported = true
            return true
        }
        if first { onFirstMessages?() }
    }

    public static func mark(_ step: String) {
        let elapsed: Duration? = lock.withLock { start.map { .now - $0 } }
        guard let elapsed else { return }
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        signposter.emitEvent("step", "\(step, privacy: .public)")
        log.notice("open \(label, privacy: .public): \(step, privacy: .public) at \(String(format: "%.0f", ms), privacy: .public) ms")
    }
}
