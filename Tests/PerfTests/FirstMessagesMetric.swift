import XCTest

/// Launch to the first #one messages, timed by the app itself: from the moment the kernel
/// started the process to the first timeline with five items (StartTrace.firstMessages). The
/// app writes the seconds to the file `IPHONEBLOG_PERF_START` names; this metric clears it
/// before each iteration and reads it after. XCTClockMetric around a launch adds XCTest's own
/// launch and polling, which hid a second of start-up waits (2026-11-20, docs/performance.md).
final class FirstMessagesMetric: NSObject, XCTMetric {
    let path: String
    private var seconds: Double?

    init(path: String) { self.path = path }

    func copy(with zone: NSZone? = nil) -> Any { FirstMessagesMetric(path: path) }

    func willBeginMeasuring() {
        try? FileManager.default.removeItem(atPath: path)
        seconds = nil
    }

    func didStopMeasuring() {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return }
        seconds = object["first_messages_s"]
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp,
                            to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        guard let seconds else { throw FirstMessagesMetricError.notWritten }
        return [XCTPerformanceMeasurement(identifier: "de.iphoneblog.first-messages", displayName: "First messages",
                                          doubleValue: seconds, unitSymbol: "s")]
    }
}

enum FirstMessagesMetricError: Error {
    /// The app wrote no time: not launched with IPHONEBLOG_PERF_START, or no timeline filled.
    case notWritten
}
