import XCTest

/// The hitch time ratio of a measured block, counted by the app itself.
///
/// Xcode reports `XCTOSSignpostMetric`'s hitch numbers only on a device; in the simulator it
/// gives scroll durations alone. So the app, launched with `IPHONEBLOG_FPS=1`, runs its
/// frame-rate readout (App/Sources/Perf/FrameRateOverlay.swift) and writes totals of frames
/// drawn while something scrolls, late frames and hitch time to the file
/// `IPHONEBLOG_PERF_STATS` names. This metric reads the file before and after each iteration
/// and reports the difference:
///
/// - **Hitch time ratio**, ms of hitch per second of scrolling, Apple's "good" under 5;
/// - **Late frames**, frames that came more than half a frame after their slot.
///
/// It measures main-thread stalls, which is what a hitch on a device mostly is; the simulator
/// draws on the Mac's GPU, so render-server hitches are a device's to find (MetricKit).
/// The simulator shares the Mac's file system, so the app and this runner see the same path.
final class HitchMetric: NSObject, XCTMetric {
    let statsPath: String
    private var start: [String: Double] = [:]
    private var end: [String: Double] = [:]

    init(statsPath: String) {
        self.statsPath = statsPath
    }

    func copy(with zone: NSZone? = nil) -> Any { HitchMetric(statsPath: statsPath) }

    func willBeginMeasuring() { start = read() }

    func didStopMeasuring() {
        // The app publishes its totals every 0.1 s; let the last frames of the block arrive.
        Thread.sleep(forTimeInterval: 0.3)
        end = read()
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp,
                            to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        let seconds = (end["scroll_seconds"] ?? 0) - (start["scroll_seconds"] ?? 0)
        let hitch = (end["hitch_ms"] ?? 0) - (start["hitch_ms"] ?? 0)
        let late = (end["late"] ?? 0) - (start["late"] ?? 0)
        // On a device the app cannot write to the runner's files: no totals, and Xcode's own
        // XCTOSSignpostMetric reports the hitch ratio there instead. The gate fails a simulator
        // run that lacks the metric.
        if start.isEmpty && end.isEmpty { return [] }
        guard seconds > 0 else { throw HitchMetricError.noFrames }
        return [
            XCTPerformanceMeasurement(identifier: "de.iphoneblog.hitch-ratio", displayName: "Hitch time ratio",
                                      doubleValue: hitch / seconds, unitSymbol: "ms/s"),
            XCTPerformanceMeasurement(identifier: "de.iphoneblog.late-frames", displayName: "Late frames",
                                      doubleValue: late, unitSymbol: "frames"),
        ]
    }

    private func read() -> [String: Double] {
        guard let data = FileManager.default.contents(atPath: statsPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return [:] }
        return object
    }
}

enum HitchMetricError: Error {
    /// Nothing scrolled, or the app wrote no totals (not launched with IPHONEBLOG_FPS=1 and
    /// IPHONEBLOG_PERF_STATS).
    case noFrames
}
