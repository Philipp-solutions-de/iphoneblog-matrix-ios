import XCTest
@testable import iphoneblog

@MainActor
final class RouterTests: XCTestCase {
    /// The app opens on the Blog tab, signed in or not.
    func testStartsOnBlog() {
        XCTAssertEqual(Router().tab, .blog)
    }

    /// A thread opens over its room in #one-Chat, from any tab, so back leads into the room.
    func testOpenThreadPutsItOverItsRoom() {
        let router = Router()
        router.tab = .forYou
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.tab, .chat)
        XCTAssertEqual(router.chatPath, [.room("!a"), .thread(Router.ThreadRoute(roomID: "!a", rootEventID: "$root"))])
        XCTAssertEqual(router.selectedRoomID, "!a")
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
        XCTAssertEqual(router.chatPath, [.room("!a"), .thread(.init(roomID: "!a", rootEventID: "$root"))])
        XCTAssertTrue(router.isOnScreen(roomID: "!a", threadRootEventID: "$root"))
        XCTAssertFalse(router.isOnScreen(roomID: "!a", threadRootEventID: "$reply"))
    }

    /// A push or link into an article thread opens it in the Blog tab, not in #one-Chat.
    func testBlogThreadOpensInBlogTab() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.tab = .forYou
        router.openThread(roomID: "!blog", rootEventID: "$article")
        XCTAssertEqual(router.tab, .blog)
        XCTAssertEqual(router.blogPath, [.thread(rootEventID: "$article")])
        XCTAssertNil(router.selectedRoomID)
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
