import Darwin
import Foundation
import UIKit
import os

/// Times the app's start, step by step, in the log (category "start"): milliseconds since the
/// app's model was made, so a slow step between launch and the first room shows by name.
enum StartTrace {
    private static let log = Logger(subsystem: "de.iphoneblog.chat", category: "start")
    nonisolated(unsafe) private static var origin: ContinuousClock.Instant?
    nonisolated(unsafe) private static var steps: [String] = []

    static func begin() { origin = .now; steps = []; log.notice("start: begin") }

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
        // The last launch, for "Ladezeit" in Ich: testers copy it into a chat (2026-11-21).
        var last = UserDefaults.standard.dictionary(forKey: lastKey) as? [String: Double] ?? [:]
        if key == "first_messages_s" { last = [:] }
        last[key] = seconds
        UserDefaults.standard.set(last, forKey: lastKey)
        UserDefaults.standard.set(steps, forKey: stepsKey)
        guard let path = ProcessInfo.processInfo.environment["IPHONEBLOG_PERF_START"] else { return }
        let url = URL(fileURLWithPath: path)
        var object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Double]) ?? [:]
        object[key] = seconds
        if let data = try? JSONSerialization.data(withJSONObject: object) { try? data.write(to: url, options: .atomic) }
    }

    private static let lastKey = "startTrace.last"
    private static let stepsKey = "startTrace.steps"

    /// "1,9 s, aktuell nach 2,0 s": the last launch to the first #one message and to fresh data.
    static var lastSummary: String? {
        guard let last = UserDefaults.standard.dictionary(forKey: lastKey) as? [String: Double],
              let first = last["first_messages_s"] else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))
        var text = "\(first.formatted(format)) s"
        if let fresh = last["fresh_s"] { text += ", aktuell nach \(fresh.formatted(format)) s" }
        return text
    }

    /// The whole last launch, as a tester sends it: build, device, times and every step.
    static var lastReport: String {
        var lines = ["iPhoneBlog \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)), \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"]
        if let summary = lastSummary { lines.append("Erste Nachricht in #one: " + summary) }
        lines += (UserDefaults.standard.stringArray(forKey: stepsKey) ?? []).map { "  " + $0 }
        return lines.joined(separator: "\n")
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
        steps.append("\(String(format: "%5.0f", ms)) ms  \(step)")
    }
}
