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
        router.tab = .mentions
        router.openThread(roomID: "!a", rootEventID: "$root")
        XCTAssertEqual(router.tab, .chat)
        XCTAssertEqual(router.chatPath, [.room("!a"), .thread(Router.ThreadRoute(roomID: "!a", rootEventID: "$root"))])
        XCTAssertEqual(router.selectedRoomID, "!a")
    }

    /// From the Threads list or a search, a thread replaces them.
    func testThreadFromTheThreadsListReplacesIt() {
        let router = Router()
        router.openThreadsList()
        router.openThread(roomID: "!b", rootEventID: "$r")
        XCTAssertEqual(router.chatPath.first, .room("!b"))
        XCTAssertFalse(router.chatPath.contains(.threads))
    }

    /// A push or link into an article thread opens it in the Blog tab, not in #one-Chat.
    func testBlogThreadOpensInBlogTab() {
        let router = Router()
        router.blogRoomID = "!blog"
        router.tab = .mentions
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
}
