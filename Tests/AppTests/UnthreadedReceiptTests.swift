import XCTest
@testable import iphoneblog

/// When the room's own timeline also sends an unthreaded receipt (ChatSession+Receipts.swift).
final class UnthreadedReceiptTests: XCTestCase {
    private let now = Date()

    func testSentForTheNewestEvent() {
        XCTAssertTrue(UnthreadedReceipt.shouldSend(viewed: now, latest: now, unreadThreadMentions: 0))
        // The room list's newest event can lag behind what the timeline already shows.
        XCTAssertTrue(UnthreadedReceipt.shouldSend(viewed: now, latest: now.addingTimeInterval(-5), unreadThreadMentions: 0))
    }

    func testNotForAnOlderEvent() {
        // Something newer (a thread reply, say) is in the room: it is not read yet.
        XCTAssertFalse(UnthreadedReceipt.shouldSend(viewed: now.addingTimeInterval(-5), latest: now, unreadThreadMentions: 0))
    }

    func testHeldBackWhileAThreadMentionIsUnread() {
        // An unthreaded receipt would mark the thread mention read without anyone seeing it.
        XCTAssertFalse(UnthreadedReceipt.shouldSend(viewed: now, latest: now, unreadThreadMentions: 1))
    }

    func testNothingWhenATimeIsUnknown() {
        XCTAssertFalse(UnthreadedReceipt.shouldSend(viewed: nil, latest: now, unreadThreadMentions: 0))
        XCTAssertFalse(UnthreadedReceipt.shouldSend(viewed: now, latest: nil, unreadThreadMentions: 0))
    }
}
