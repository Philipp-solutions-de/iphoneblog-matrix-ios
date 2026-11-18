import XCTest
@testable import iphoneblog

/// Where the room's own timeline puts its unthreaded receipt (ChatSession+Receipts.swift).
final class UnthreadedReceiptTests: XCTestCase {
    private func message(_ id: String) -> UnthreadedReceipt.Event { .init(id: id, isVisible: true) }
    private func hidden(_ id: String) -> UnthreadedReceipt.Event { .init(id: id, isVisible: false) }

    func testOnTheMessageReadWhenItIsTheNewest() {
        XCTAssertEqual(UnthreadedReceipt.target(read: "$m", newestFirst: [message("$m"), message("$old")]), "$m")
    }

    /// Philip's #bugs: a reaction and its redaction after the last message. The receipt goes on
    /// the redaction, so the server's count for the room drops to 0.
    func testOnTheNewestHiddenEventAfterTheMessageRead() {
        XCTAssertEqual(UnthreadedReceipt.target(read: "$m", newestFirst: [hidden("$redaction"), hidden("$reaction"), message("$m")]),
                       "$redaction")
    }

    /// A newer message, in the room or in a thread, is not read yet.
    func testNothingWhenAnUnseenMessageIsNewer() {
        XCTAssertNil(UnthreadedReceipt.target(read: "$m", newestFirst: [hidden("$r"), message("$thread-reply"), message("$m")]))
    }

    func testNothingWhenTheMessageReadIsOutOfReach() {
        XCTAssertNil(UnthreadedReceipt.target(read: "$m", newestFirst: [hidden("$a"), hidden("$b")]))
        XCTAssertNil(UnthreadedReceipt.target(read: "$m", newestFirst: []))
    }

    /// The main receipt goes on the newest hidden event the server files under "main".
    func testMainReceiptOnTheNewestMainEvent() {
        let read = message("$m")
        let reaction = UnthreadedReceipt.Event(id: "$react", isVisible: false, thread: nil, relatesTo: "$m")
        let redaction = hidden("$redaction")
        XCTAssertEqual(UnthreadedReceipt.mainTarget(read: "$m", newestFirst: [redaction, reaction, read]), "$redaction")
        XCTAssertEqual(UnthreadedReceipt.mainTarget(read: "$m", newestFirst: [reaction, read]), "$react")
        XCTAssertEqual(UnthreadedReceipt.mainTarget(read: "$m", newestFirst: [read]), "$m")
    }

    /// A reaction on a thread reply belongs to the thread: no main receipt on it.
    func testNoMainReceiptOnAThreadsReaction() {
        let reply = UnthreadedReceipt.Event(id: "$reply", isVisible: true, thread: "$root")
        let reaction = UnthreadedReceipt.Event(id: "$react", isVisible: false, thread: nil, relatesTo: "$reply")
        // The reply itself is newer than the message read, so nothing at all.
        XCTAssertNil(UnthreadedReceipt.mainTarget(read: "$m", newestFirst: [reaction, reply, message("$m")]))
        // Its target out of sight: unknown thread, so the main receipt stays on the message read.
        XCTAssertEqual(UnthreadedReceipt.mainTarget(read: "$m", newestFirst: [UnthreadedReceipt.Event(id: "$r2", isVisible: false, thread: nil, relatesTo: "$far"), message("$m")]), "$m")
    }

    func testWhatCountsAsHidden() {
        func event(_ json: [String: Any]) -> Bool { UnthreadedReceipt.Event(json).isVisible }
        XCTAssertFalse(event(["event_id": "$1", "type": "m.room.redaction"]))
        XCTAssertFalse(event(["event_id": "$2", "type": "m.reaction"]))
        XCTAssertFalse(event(["event_id": "$3", "type": "m.room.member", "state_key": "@a:x"]))
        XCTAssertFalse(event(["event_id": "$4", "type": "m.room.message", "content": ["m.relates_to": ["rel_type": "m.replace"]]]))
        XCTAssertTrue(event(["event_id": "$5", "type": "m.room.message", "content": ["body": "hi"]]))
        XCTAssertTrue(event(["event_id": "$6", "type": "m.room.message", "content": ["m.relates_to": ["rel_type": "m.thread"]]]))
    }
}
