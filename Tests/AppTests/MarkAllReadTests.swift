import XCTest
@testable import iphoneblog

/// "Alle als gelesen" sends receipts for exactly what @Mentions lists (MentionsModel.receipts).
final class MarkAllReadTests: XCTestCase {
    private func mention(_ id: String, room: String, thread: String?, at seconds: Double) -> MentionsModel.Mention {
        MentionsModel.Mention(id: id, roomID: room, place: .room(roomID: room, name: nil), senderID: "@a:x", senderName: "A",
                              body: "", date: Date(timeIntervalSince1970: seconds), threadRoot: thread, unread: true)
    }

    private func bodies(_ receipts: [MentionsModel.Receipt]) -> [String] {
        receipts.map { (String(data: $0.path.data(using: .utf8)!, encoding: .utf8) ?? "") + " " + String(decoding: $0.body, as: UTF8.self) }
    }

    func testNewestPerThreadAndPerTimeline() {
        let receipts = MentionsModel.receipts(for: [
            mention("$m1", room: "!a", thread: nil, at: 1), mention("$m2", room: "!a", thread: nil, at: 2),
            mention("$t1", room: "!a", thread: "$root", at: 3), mention("$t2", room: "!a", thread: "$root", at: 4),
            mention("$b1", room: "!b", thread: "$other", at: 5),
        ])
        XCTAssertEqual(bodies(receipts), [
            #"/_matrix/client/v3/rooms/!a/receipt/m.read/$t2 {"thread_id":"$root"}"#,
            #"/_matrix/client/v3/rooms/!a/receipt/m.read/$m2 {"thread_id":"main"}"#,
            #"/_matrix/client/v3/rooms/!b/receipt/m.read/$b1 {"thread_id":"$other"}"#,
        ])
    }
}
