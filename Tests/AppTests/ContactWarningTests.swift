import ChatKit
import XCTest

/// What counts as contact details before a message goes out (ChatContactWarning).
@MainActor
final class ContactWarningTests: XCTestCase {
    func testFindsEmailAndPhoneNumbers() {
        XCTAssertEqual(ChatContactWarning.contactData(in: "Schreib mir: tim.b@example.org"), ["tim.b@example.org"])
        for number in ["+49 170 1234567", "0170/1234567", "089-123 456 78", "+4917012345678", "0170 123 45 67"] {
            XCTAssertEqual(ChatContactWarning.contactData(in: "Ruf an: \(number) bis 18 Uhr"), [number], number)
        }
        XCTAssertEqual(ChatContactWarning.contactData(in: "a@b.de oder 0170 1234567"), ["a@b.de", "0170 1234567"])
    }

    func testLeavesOrdinaryTextAlone() {
        for text in ["Menütest 1794903369", "Am 01.12.2026 um 18:30", "Kostet 1.299 €", "iPhone 17 Pro mit 256 GB",
                     "@thorsten:iphoneblog.de hat recht", "https://www.iphoneblog.de/2026/08/17/titel/",
                     "Ticket 12345678", "Die PLZ ist 83278", "Version 0.5.7"] {
            XCTAssertEqual(ChatContactWarning.contactData(in: text), [], text)
        }
    }
}

/// A thread row's count (ChatThreadCount): "Noch keine Antworten" only without replies and repliers.
@MainActor
final class ThreadCountTests: XCTestCase {
    func testTheServersCountWins() {
        XCTAssertEqual(ChatThreadCount.replies(server: 7, timeline: 3, repliers: 3), 7)
        XCTAssertEqual(ChatThreadCount.replies(server: nil, timeline: 4, repliers: 2), 4)
    }

    /// Thorsten's screenshot: three repliers, "Noch keine Antworten" (a failed fetch had stored 0).
    func testRepliersNeverShowZero() {
        XCTAssertEqual(ChatThreadCount.replies(server: 0, timeline: 0, repliers: 3), 3)
        XCTAssertEqual(ChatThreadCount.replies(server: nil, timeline: 0, repliers: 0), 0)
    }
}
