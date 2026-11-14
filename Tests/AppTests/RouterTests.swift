import XCTest
@testable import iphoneblog

@MainActor
final class RouterTests: XCTestCase {
    /// From another tab the thread waits until the channel's stack exists (ChatsView opens it).
    func testOpenThreadFromAnotherTabSelectsChannelAndQueuesThread() {
        let router = Router()
        router.tab = .threads
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.tab, .chats)
        XCTAssertEqual(router.selectedRoomID, "!a")
        XCTAssertEqual(router.pendingThread, Router.ThreadRoute(roomID: "!a", rootEventID: "$root"))
        XCTAssertTrue(router.threadPath.isEmpty)
    }

    /// Inside the open channel the thread opens at once.
    func testOpenThreadInOpenChannelPushesDirectly() {
        let router = Router()
        router.openRoom("!a")
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.threadPath, [Router.ThreadRoute(roomID: "!a", rootEventID: "$root")])
        XCTAssertNil(router.pendingThread)
    }
}
