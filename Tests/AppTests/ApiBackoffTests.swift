import XCTest
@testable import iphoneblog

/// What pauses the app's own calls (ChatSession.countsAsOutage).
final class ApiBackoffTests: XCTestCase {
    func testOutagesCountAndCancelsDoNot() {
        XCTAssertTrue(ChatSession.countsAsOutage(.timedOut, status: 0))
        XCTAssertTrue(ChatSession.countsAsOutage(.notConnectedToInternet, status: 0))
        XCTAssertTrue(ChatSession.countsAsOutage(.badServerResponse, status: 502))
        XCTAssertFalse(ChatSession.countsAsOutage(.badServerResponse, status: 404))
        XCTAssertFalse(ChatSession.countsAsOutage(.cancelled, status: 0), "a search cancelled by the next keystroke paused every call")
        XCTAssertFalse(ChatSession.countsAsOutage(.userAuthenticationRequired, status: 0))
    }
}
