import XCTest
@testable import iphoneblog

@MainActor
final class RouterTests: XCTestCase {
    /// The app opens on the Blog tab, signed in or not.
    func testStartsOnBlog() {
        XCTAssertEqual(Router().tab, .blog)
    }

    /// From another tab a channel's thread waits until the channel's stack exists.
    func testOpenThreadFromAnotherTabSelectsChannelAndQueuesThread() {
        let router = Router()
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.tab, .chat)
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

    /// A push or link into an article thread opens it in the Blog tab, not in #one-Chat.
    func testBlogThreadOpensInBlogTab() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.tab = .mentions
        router.openThread(roomID: "!blog", rootEventID: "$article")
        XCTAssertEqual(router.tab, .blog)
        XCTAssertEqual(router.blogPath, ["$article"])
        XCTAssertNil(router.selectedRoomID)
    }

    /// Signing out leaves the Blog tab, readable, and nothing of the account.
    func testResetAfterSignOut() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.openRoom("!a")
        router.reset()
        XCTAssertEqual(router.tab, .blog)
        XCTAssertNil(router.selectedRoomID)
        XCTAssertNil(router.blogRoomID)
    }
}
