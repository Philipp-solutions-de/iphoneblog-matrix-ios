import ChatKit
import XCTest

/// The row's movement for a pan (Shim/MessageSwipe.swift). Inside a thread a right swipe moves
/// nothing, so neither the thread icon shows nor the action fires (Philip, 2026-11-18).
final class MessageSwipeTests: XCTestCase {
    func testRightSwipeMovesTheRowInTheRoom() {
        XCTAssertGreaterThan(MessageSwipeMath.offset(dx: 200, allowsRight: true), 50, "past the action threshold")
    }

    func testRightSwipeMovesNothingInsideAThread() {
        XCTAssertEqual(MessageSwipeMath.offset(dx: 200, allowsRight: false), 0)
        XCTAssertEqual(MessageSwipeMath.offset(dx: 1000, allowsRight: false), 0)
    }

    func testLeftSwipeStillWorksInsideAThread() {
        XCTAssertLessThan(MessageSwipeMath.offset(dx: -200, allowsRight: false), -50)
        XCTAssertEqual(MessageSwipeMath.offset(dx: -200, allowsRight: false), MessageSwipeMath.offset(dx: -200, allowsRight: true))
    }
}
