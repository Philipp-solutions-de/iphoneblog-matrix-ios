import MatrixRustSDK
import XCTest
@testable import iphoneblog

/// A thread whose root lies far back in its room (an older article in the Blog room, Philip's
/// case): the SDK's thread timeline starts with the synced replies only, and paging back brings
/// the root, which the thread screen needs for its first message and the reply count.
@MainActor
final class ThreadRootTests: XCTestCase {
    func testThreadTimelineHoldsAnOldRoot() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let store = SessionStore(service: "thread-root-tests.\(UUID().uuidString)")
        defer { store.delete() }
        let model = AppModel(homeserverURL: server, store: store)
        await model.signIn(username: user, password: password)
        guard case .signedIn(let session) = model.state else {
            return XCTFail("not signed in: \(model.errorMessage ?? "no message")")
        }

        let created = try await session.api("POST", "/_matrix/client/v3/createRoom",
                                            body: Data(#"{"name":"Alter Thread","preset":"private_chat"}"#.utf8))
        let roomID = try XCTUnwrap((JSONSerialization.jsonObject(with: created) as? [String: Any])?["room_id"] as? String)
        let encoded = try XCTUnwrap(roomID.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        var txn = 0
        func send(_ content: [String: Any]) async throws -> String {
            txn += 1
            let data = try await session.api("PUT", "/_matrix/client/v3/rooms/\(encoded)/send/m.room.message/r\(Int(Date().timeIntervalSince1970))\(txn)",
                                             body: try JSONSerialization.data(withJSONObject: content))
            return try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["event_id"] as? String)
        }
        // As in the Blog room: the app syncs the room while the thread starts, then newer
        // articles push the root back.
        let joined = Date().addingTimeInterval(30)
        while Date() < joined, (try? session.client.getRoom(roomId: roomID)) == nil {
            try await Task.sleep(for: .milliseconds(250))
        }
        let root = try await send(["msgtype": "m.text", "body": "Ein alter Artikel"])
        let reply = try await send(["msgtype": "m.text", "body": "Alte Antwort",
                                    "m.relates_to": ["rel_type": "m.thread", "event_id": root, "is_falling_back": true,
                                                     "m.in_reply_to": ["event_id": root]]])
        try await Task.sleep(for: .seconds(4)) // the sync takes root and reply into the cache
        for n in 1...40 { _ = try await send(["msgtype": "m.text", "body": "Neuerer Artikel \(n)"]) }
        try await Task.sleep(for: .seconds(4))

        let synced = Date().addingTimeInterval(30)
        while Date() < synced, (try? session.client.getRoom(roomId: roomID)) == nil {
            try await Task.sleep(for: .milliseconds(250))
        }
        let room = try XCTUnwrap(try session.client.getRoom(roomId: roomID), "the room did not sync")
        let timeline = try await room.timelineWithConfiguration(configuration: .init(focus: .thread(rootEventId: root),
                                                                                    filter: .all,
                                                                                    internalIdPrefix: nil,
                                                                                    dateDividerMode: .daily,
                                                                                    trackReadReceipts: .messageLikeEvents,
                                                                                    reportUtds: false))
        let items = TimelineItems()
        let handle = await timeline.addListener(listener: items)
        defer { handle.cancel() }
        // What the thread screen gets at first: the synced reply, not the root; one page back
        // brings the root (ChatThreadCoordinator.loadRoot pages back for it).
        try await Task.sleep(for: .seconds(1))
        var reachedStart = false
        for _ in 0..<5 where !items.eventIDs.contains(root) {
            reachedStart = (try? await timeline.paginateBackwards(numEvents: 20)) ?? false
            try await Task.sleep(for: .milliseconds(300))
        }
        let ids = items.eventIDs
        XCTAssertTrue(ids.contains(reply), "the reply is not in the thread timeline: \(ids)")
        XCTAssertTrue(ids.contains(root), "the root is not in the thread timeline (start reached: \(reachedStart)): \(ids)")

        _ = try? await session.api("POST", "/_matrix/client/v3/rooms/\(encoded)/leave", body: Data("{}".utf8))
        _ = try? await session.api("POST", "/_matrix/client/v3/rooms/\(encoded)/forget", body: Data("{}".utf8))
        await model.signOut()
    }
}

/// The timeline's items, by event ID, as the listener's diffs leave them.
private final class TimelineItems: TimelineListener, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TimelineItem] = []

    var eventIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { item in
            guard case .eventId(let id) = item.asEvent()?.eventOrTransactionId else { return nil }
            return id
        }
    }

    func onUpdate(diff: [TimelineDiff]) {
        lock.lock()
        defer { lock.unlock() }
        for change in diff {
            switch change {
            case .append(let values): items.append(contentsOf: values)
            case .clear: items.removeAll()
            case .pushFront(let value): items.insert(value, at: 0)
            case .pushBack(let value): items.append(value)
            case .popFront: if !items.isEmpty { items.removeFirst() }
            case .popBack: if !items.isEmpty { items.removeLast() }
            case .insert(let index, let value): items.insert(value, at: min(Int(index), items.count))
            case .set(let index, let value): if Int(index) < items.count { items[Int(index)] = value }
            case .remove(let index): if Int(index) < items.count { items.remove(at: Int(index)) }
            case .truncate(let length): items = Array(items.prefix(Int(length)))
            case .reset(let values): items = values
            }
        }
    }
}
