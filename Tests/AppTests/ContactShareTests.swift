import XCTest
@testable import iphoneblog

/// "Kontaktdaten teilen" against the server's contract (infra docs/matrix.md).
@MainActor
final class ContactShareTests: XCTestCase {
    func testRequestCarriesPhoneOnlyWhenChosen() throws {
        let both = ContactShare.request(to: "@rudi:iphoneblog.de", fields: [.email, .phone], phone: " +49 170 1234567 ", note: "  Hallo  ")
        XCTAssertEqual(try json(both), ["to": "@rudi:iphoneblog.de", "fields": ["email", "phone"], "phone": "+49 170 1234567", "note": "Hallo"])
        let email = ContactShare.request(to: "@rudi:iphoneblog.de", fields: [.email], phone: "0170 1234567", note: " ")
        XCTAssertEqual(try json(email), ["to": "@rudi:iphoneblog.de", "fields": ["email"]])
    }

    func testPhoneNumbersAsTheServerAccepts() {
        for ok in ["+49 170 1234567", "0170/1234567", "(089) 123-456", "123456"] { XCTAssertTrue(ContactShare.isPhoneNumber(ok), ok) }
        for bad in ["12345", "0170 12345678901234567", "0170 123 abc", "", "+49 170 1234567 ext. 2"] {
            XCTAssertFalse(ContactShare.isPhoneNumber(bad), bad)
        }
    }

    func testOnlyWithAnotherPerson() {
        XCTAssertTrue(ContactShare.canShare(with: "@rudi:iphoneblog.de", me: "@tim:iphoneblog.de"))
        XCTAssertFalse(ContactShare.canShare(with: "@tim:iphoneblog.de", me: "@tim:iphoneblog.de"))
        XCTAssertFalse(ContactShare.canShare(with: "@iphoneblog:iphoneblog.de", me: "@tim:iphoneblog.de"))
    }

    func testRefusalsBecomeGermanMessages() {
        let limit = Data(#"{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":125000}"#.utf8)
        XCTAssertEqual(ContactShare.Failure.from(status: 429, body: limit), .tooMany(retryMinutes: 3))
        XCTAssertEqual(ContactShare.Failure.from(status: 404, body: Data()), .recipientUnavailable)
        XCTAssertEqual(ContactShare.Failure.from(status: 403, body: Data()), .notMember)
        XCTAssertEqual(ContactShare.Failure.from(status: 502, body: Data()), .mailFailed)
        XCTAssertEqual(ContactShare.Failure.from(status: 500, body: Data()), .other)
    }

    private func json(_ request: ContactShare.Request) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary)
    }
}
