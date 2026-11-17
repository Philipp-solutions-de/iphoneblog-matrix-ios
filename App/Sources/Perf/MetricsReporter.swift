import Foundation
import MetricKit
import os
import StoreKit
import UIKit

/// The numbers a real iPhone measures, sent home once a day (docs/performance.md).
///
/// iOS collects MetricKit metrics for the app and hands them over about once every 24 hours,
/// diagnostics (hangs) as they happen on iOS 15 and later. This keeps a handful of numbers from
/// each payload and sends them as the query string of one POST to the blog's `/rum` path, where
/// `edge` answers 204 itself and its log line is the report (infra, `edge`, "the speed reports").
///
/// **What it sends, and nothing else:** app version and build, device model, iOS version, the
/// screen's maximum frame rate (once per build, and with every report), the scroll hitch time ratio, launch time to first frame (median),
/// and the number and longest duration of hangs; and why a session ended or survived a token
/// error (AuthGuard: outcome, the path's shape with IDs blanked, the errcode, the number of
/// checks). No message, no room, no user ID, no call stack.
/// The request carries no cookie and no token.
///
/// **TestFlight only (GDPR, Thorsten 2026-11-17).** An App Store build sends nothing. The same
/// binary goes from TestFlight to the App Store unchanged, so a build setting cannot tell them
/// apart: StoreKit's AppTransaction says where this copy came from, and only `.sandbox`
/// (TestFlight) and `.xcode` report. Unknown, unverifiable or `.production`: off.
/// scripts/check-release-clean.sh fails a build without this gate ("rum-gate-v1").
final class MetricsReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsReporter()

    /// Whether this copy may report. Off until StoreKit has answered.
    private let allowed = OSAllocatedUnfairLock(initialState: false)
    static let gateMarker = "rum-gate-v1"

    /// The rule: TestFlight and Xcode builds report, the App Store never, and unknown never.
    static func mayReport(_ environment: AppStore.Environment?) -> Bool {
        environment == .sandbox || environment == .xcode
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// `https://<the Blog tab's host>/rum`: www in a release, beta while the Blog tab points there.
    /// Both take the report before their gate.
    private var endpoint: URL? {
        guard let host = URL(string: Brand.blogWebURL)?.host else { return nil }
        return URL(string: "https://\(host)/rum")
    }

    private var maxFPS = 0

    /// Called once at launch. Registers with MetricKit; MetricKit only delivers on a device.
    @MainActor
    func start() {
        maxFPS = UIScreen.main.maximumFramesPerSecond
        Task { @MainActor in
            let transaction = try? await AppTransaction.shared
            let environment: AppStore.Environment? = switch transaction {
            case .verified(let app)?: app.environment
            default: nil
            }
            // The marker string stays in the binary through this log line; the release check looks for it.
            guard Self.mayReport(environment) else {
                Logger(subsystem: Brand.bundleID, category: "metrics").info("\(Self.gateMarker, privacy: .public): off in this build")
                return
            }
            allowed.withLock { $0 = true }
            startReporting()
        }
    }

    @MainActor
    private func startReporting() {
        MXMetricManager.shared.add(self)
        // **Once per build: the screen's frame rate**, so the first report proves 120 Hz on a
        // ProMotion iPhone the day a tester installs the build, before MetricKit's first payload.
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let key = "perf.reportedFrameRateForBuild"
        if UserDefaults.standard.string(forKey: key) != build, !ProcessInfo.processInfo.isRunningPerfTests {
            UserDefaults.standard.set(build, forKey: key)
            send(["kind": "install", "dev": Self.model])
        }
        // **A self-test for the path, not for the numbers**: one report with `kind=selftest`, so a
        // simulator run can prove the request reaches `edge` (docs/performance.md).
        if ProcessInfo.processInfo.environment["IPHONEBLOG_METRICS_SELFTEST"] == "1" {
            send(["kind": "selftest", "hitch": "0.0"])
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { send(Self.fields(of: payload)) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let hangs = payload.hangDiagnostics ?? []
            guard !hangs.isEmpty else { continue }
            let longest = hangs.map { $0.hangDuration.converted(to: .milliseconds).value }.max() ?? 0
            var fields: [String: String] = ["kind": "hang", "hang_n": "\(hangs.count)", "hang_ms": "\(Int(longest))"]
            if let meta = hangs.first?.metaData { fields.merge(Self.fields(of: meta)) { a, _ in a } }
            send(fields)
        }
    }

    // MARK: The fields

    static func fields(of payload: MXMetricPayload) -> [String: String] {
        var f: [String: String] = ["kind": "metrics"]
        if let meta = payload.metaData { f.merge(fields(of: meta)) { a, _ in a } }
        if let hitch = payload.animationMetrics?.scrollHitchTimeRatio {
            // MetricKit's unit is milliseconds of hitch per second of scrolling, Apple's "ms/s".
            f["hitch"] = String(format: "%.1f", hitch.value)
        }
        if let launch = payload.applicationLaunchMetrics {
            if let (median, count) = median(launch.histogrammedTimeToFirstDraw) {
                f["launch_ms"] = "\(Int(median))"
                f["launch_n"] = "\(count)"
            }
            if let (median, _) = median(launch.histogrammedOptimizedTimeToFirstDraw) {
                f["launch_opt_ms"] = "\(Int(median))"
            }
        }
        if let hangs = payload.applicationResponsivenessMetrics?.histogrammedApplicationHangTime,
           let (median, count) = median(hangs) {
            f["hang_n"] = "\(count)"
            f["hang_ms"] = "\(Int(median))"
        }
        return f
    }

    static func fields(of meta: MXMetaData) -> [String: String] {
        ["b": meta.applicationBuildVersion, "dev": meta.deviceType, "os": meta.osVersion]
    }

    /// The median of a MetricKit histogram, in milliseconds: the middle of the bucket that holds
    /// the middle count. Nil for an empty histogram.
    static func median(_ histogram: MXHistogram<UnitDuration>) -> (Double, Int)? {
        var buckets: [(mid: Double, count: Int)] = []
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            let start = bucket.bucketStart.converted(to: .milliseconds).value
            let end = bucket.bucketEnd.converted(to: .milliseconds).value
            buckets.append(((start + end) / 2, bucket.bucketCount))
        }
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        var seen = 0
        for bucket in buckets {
            seen += bucket.count
            if seen * 2 >= total { return (bucket.mid, total) }
        }
        return nil
    }

    /// The device model, as MetricKit names it ("iPhone17,1").
    static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    // MARK: Sending

    /// One line for an event worth seeing on the server, such as why a session ended
    /// (AuthGuard): the same POST, the same rules (no user, no token, nothing from a simulator).
    func breadcrumb(_ fields: [String: String]) {
        guard !ProcessInfo.processInfo.isRunningPerfTests else { return }
        send(fields)
    }

    private func send(_ fields: [String: String]) {
        guard allowed.withLock({ $0 }), let endpoint, var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        var all = fields
        all["src"] = "ios"
        all["v"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        all["b"] = all["b"] ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
        all["hz"] = "\(maxFPS)"
        parts.queryItems = all.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        session.dataTask(with: request).resume()
    }
}

private extension ProcessInfo {
    /// A simulator, or a UI or performance test pointing the app at a test server or fixture:
    /// it reports nothing home.
    var isRunningPerfTests: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return environment["IPHONEBLOG_PERF_STATS"] != nil || environment["IPHONEBLOG_HOMESERVER"] != nil
            || environment["IPHONEBLOG_BLOG_WEB"] != nil
        #endif
    }
}
