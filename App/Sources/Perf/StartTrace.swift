import Darwin
import Foundation
import os

/// Times the app's start, step by step, in the log (category "start"): milliseconds since the
/// app's model was made, so a slow step between launch and the first room shows by name.
enum StartTrace {
    private static let log = Logger(subsystem: "de.iphoneblog.chat", category: "start")
    nonisolated(unsafe) private static var origin: ContinuousClock.Instant?

    static func begin() { origin = .now; log.notice("start: begin") }

    /// The first #one messages on screen (ChatOpenTrace.onFirstMessages): seconds since the
    /// process started, in the log and, for testOneChatAfterLaunch, in the file
    /// IPHONEBLOG_PERF_START names (FirstMessagesMetric).
    static func firstMessages() {
        guard let started = processStart() else { return }
        let seconds = Date().timeIntervalSince(started)
        log.notice("start: first messages at \(String(format: "%.0f", seconds * 1000), privacy: .public) ms after launch")
        write("first_messages_s", seconds)
    }

    /// The server's rooms, membership and #one list have replaced what a warm launch showed:
    /// seconds since the process started, in the log and in the IPHONEBLOG_PERF_START file
    /// ("fresh_s", FirstMessagesMetric).
    static func fresh() {
        guard let started = processStart() else { return }
        let seconds = Date().timeIntervalSince(started)
        log.notice("start: fresh at \(String(format: "%.0f", seconds * 1000), privacy: .public) ms after launch")
        write("fresh_s", seconds)
    }

    /// Adds one number to the perf file without dropping the others.
    private static func write(_ key: String, _ seconds: Double) {
        guard let path = ProcessInfo.processInfo.environment["IPHONEBLOG_PERF_START"] else { return }
        let url = URL(fileURLWithPath: path)
        var object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Double]) ?? [:]
        object[key] = seconds
        if let data = try? JSONSerialization.data(withJSONObject: object) { try? data.write(to: url, options: .atomic) }
    }

    /// When the kernel started this process: before main, so the launch itself counts.
    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    static func mark(_ step: String) {
        guard let origin else { return }
        let elapsed = ContinuousClock.now - origin
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        log.notice("start: \(step, privacy: .public) at \(String(format: "%.0f", ms), privacy: .public) ms")
    }
}
