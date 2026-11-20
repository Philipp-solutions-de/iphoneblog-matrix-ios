import XCTest
@testable import iphoneblog

@MainActor
final class RouterTests: XCTestCase {
    /// The app opens on the Blog tab, signed in or not.
    func testStartsOnBlog() {
        XCTAssertEqual(Router().tab, .blog)
    }

    /// A thread opens over Chat in #one, from any tab, so back leads into the room under the
    /// room bar, and back again to the hub.
    func testOpenThreadPutsItOverItsRoom() {
        let router = Router()
        router.tab = .forYou
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.tab, .chat)
        XCTAssertEqual(router.chatPath, [.chat, .thread(Router.ThreadRoute(roomID: "!a", rootEventID: "$root"))])
        XCTAssertEqual(router.selectedRoomID, "!a")
    }

    /// A room opens in Chat, under the room bar, and is remembered as the last room read.
    func testOpenRoomBecomesTheCurrentRoom() {
        let router = Router()
        router.openThreadsList()
        router.openRoom("!b")
        XCTAssertEqual(router.chatPath, [.chat])
        XCTAssertEqual(router.currentRoomID, "!b")
        XCTAssertEqual(Router().currentRoomID, "!b", "the last room read is not remembered")
    }

    /// From the Threads list or a search, a thread goes on top, so back returns there.
    func testThreadFromTheThreadsListGoesOnTop() {
        let router = Router()
        router.openThreadsList()
        router.openThread(roomID: "!b", rootEventID: "$r")
        XCTAssertEqual(router.chatPath, [.threads, .thread(.init(roomID: "!b", rootEventID: "$r"))])
    }

    /// A thread opened on a reply moves to its real root, in place, and the receipts' screen
    /// check then matches the root (ResolvedThreadScreen).
    func testCorrectThreadMovesTheRouteToItsRoot() {
        let router = Router()
        router.openThread(roomID: "!a", rootEventID: "$reply")
        router.correctThread(roomID: "!a", from: "$reply", to: "$root")
        XCTAssertEqual(router.chatPath, [.chat, .thread(.init(roomID: "!a", rootEventID: "$root"))])
        XCTAssertTrue(router.isOnScreen(roomID: "!a", threadRootEventID: "$root"))
        XCTAssertFalse(router.isOnScreen(roomID: "!a", threadRootEventID: "$reply"))
    }

    /// The hub is no timeline: nothing on it sends a receipt; Chat on top is the room on screen.
    func testHubSendsNoReceiptChatDoes() {
        let router = Router()
        router.tab = .chat
        router.currentRoomID = "!a"
        router.chatPath = []
        XCTAssertFalse(router.isOnScreen(roomID: "!a", threadRootEventID: nil), "the hub counts as the room")
        router.openChat()
        XCTAssertTrue(router.isOnScreen(roomID: "!a", threadRootEventID: nil))
        router.openChat(roomID: "!b")
        XCTAssertEqual(router.currentRoomID, "!b")
        XCTAssertEqual(router.chatPath, [.chat])
    }

    /// A push or link into an article thread opens it in the Blog tab, not in #one-Chat.
    func testBlogThreadOpensInBlogTab() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.tab = .forYou
        let roomBefore = router.currentRoomID
        router.openThread(roomID: "!blog", rootEventID: "$article")
        XCTAssertEqual(router.tab, .blog)
        XCTAssertEqual(router.blogPath, [.thread(rootEventID: "$article")])
        XCTAssertEqual(router.chatPath, [])
        XCTAssertEqual(router.currentRoomID, roomBefore, "#one changed for a Blog thread")
    }

    /// Signing out leaves the Blog tab, readable, and nothing of the account.
    func testResetAfterSignOut() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.openRoom("!a")
        router.reset()
        XCTAssertEqual(router.tab, .blog)
        XCTAssertTrue(router.chatPath.isEmpty)
        XCTAssertNil(router.blogRoomID)
    }

    /// Only the timeline on top of the visible tab reads (sends receipts).
    func testOnlyTheTimelineOnTopIsOnScreen() {
        let router = Router()
        router.openRoom("!a")
        XCTAssertTrue(router.isOnScreen(roomID: "!a", threadRootEventID: nil))
        XCTAssertFalse(router.isOnScreen(roomID: "!b", threadRootEventID: nil))
        router.openThread(roomID: "!a", rootEventID: "$r")
        XCTAssertFalse(router.isOnScreen(roomID: "!a", threadRootEventID: nil), "the room under the thread is not on screen")
        XCTAssertTrue(router.isOnScreen(roomID: "!a", threadRootEventID: "$r"))
        router.tab = .me
        XCTAssertFalse(router.isOnScreen(roomID: "!a", threadRootEventID: "$r"), "a timeline behind another tab is not on screen")
    }
}
