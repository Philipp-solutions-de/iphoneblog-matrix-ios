import ChatKit
import XCTest

/// Where the reader stopped, per room and thread, on this device only (ChatReadPositions).
@MainActor
final class ReadPositionsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ChatReadPositions!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ReadPositionsTests")
        defaults.removePersistentDomain(forName: "ReadPositionsTests")
        store = ChatReadPositions(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ReadPositionsTests")
    }

    func testKeyedByUserRoomAndThread() {
        store.record("$a", user: "@me:x", room: "!r:x", thread: nil)
        store.record("$b", user: "@me:x", room: "!r:x", thread: "$root")
        store.record("$c", user: "@other:x", room: "!r:x", thread: nil)
        XCTAssertEqual(store.position(user: "@me:x", room: "!r:x", thread: nil), "$a")
        XCTAssertEqual(store.position(user: "@me:x", room: "!r:x", thread: "$root"), "$b")
        XCTAssertEqual(store.position(user: "@other:x", room: "!r:x", thread: nil), "$c")
        XCTAssertNil(store.position(user: "@me:x", room: "!other:x", thread: nil))
        XCTAssertEqual(ChatReadPositions.key(user: "@me:x", room: "!r:x", thread: nil), "readpos.@me:x.!r:x.main")
    }

    func testNilClears() {
        store.record("$a", user: "@me:x", room: "!r:x", thread: nil)
        store.record(nil, user: "@me:x", room: "!r:x", thread: nil)
        XCTAssertNil(store.position(user: "@me:x", room: "!r:x", thread: nil))
        XCTAssertNil(defaults.object(forKey: ChatReadPositions.key(user: "@me:x", room: "!r:x", thread: nil)))
    }

    func testOldestGoBeyondTheCapacity() {
        for n in 0..<(ChatReadPositions.capacity + 5) {
            store.record("$e\(n)", user: "@me:x", room: "!r\(n):x", thread: nil)
        }
        XCTAssertNil(store.position(user: "@me:x", room: "!r0:x", thread: nil), "the oldest stays")
        XCTAssertNil(store.position(user: "@me:x", room: "!r4:x", thread: nil))
        XCTAssertEqual(store.position(user: "@me:x", room: "!r5:x", thread: nil), "$e5")
        XCTAssertEqual(store.position(user: "@me:x", room: "!r\(ChatReadPositions.capacity + 4):x", thread: nil), "$e\(ChatReadPositions.capacity + 4)")
        XCTAssertEqual((defaults.dictionary(forKey: "readpos.index") ?? [:]).count, ChatReadPositions.capacity)
    }
}
