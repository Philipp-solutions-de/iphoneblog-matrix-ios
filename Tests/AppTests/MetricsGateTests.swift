import StoreKit
import XCTest
@testable import iphoneblog

/// Speed reports leave TestFlight and Xcode builds only, never an App Store copy (GDPR).
final class MetricsGateTests: XCTestCase {
    func testOnlyTestFlightAndXcodeReport() {
        XCTAssertTrue(MetricsReporter.mayReport(.sandbox))
        XCTAssertTrue(MetricsReporter.mayReport(.xcode))
        XCTAssertFalse(MetricsReporter.mayReport(.production))
        XCTAssertFalse(MetricsReporter.mayReport(nil))
    }
}
