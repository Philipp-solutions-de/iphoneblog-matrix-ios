import SQLite3
import XCTest

/// The receipts the timelines leave on the server (ChatSession+Receipts.swift):
/// a room read to its newest event moves the unthreaded receipt there, which the Rust SDK's room
/// count needs; and a thread never sends a receipt the server refuses (its root went with the
/// root as its own thread_id, a 400). Each test writes its own messages as another member.
final class ReceiptsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var room: String { env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
    }

    func testRoomReadToTheEndMovesTheUnthreadedReceipt() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        // A clean start: everything up to now read, unthreaded, so no older thread mention holds
        // the receipt back.
        let before = try other.send("Quittung vorher \(stamp)", in: room)
        try me.readReceipt(before, in: room, thread: nil)
        XCTAssertEqual(try storedReceipt(me.userID, in: room, thread: nil), before)
        var last = ""
        for n in 1...3 { last = try other.send("Quittung \(n) \(stamp)", in: room) }

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "room did not open")
        XCTAssertTrue(waitFor(30) { (try? self.storedReceipt(me.userID, in: room, thread: nil)) == last },
                      "the unthreaded receipt did not move to the newest message")
        XCTAssertEqual(try storedReceipt(me.userID, in: room, thread: "main"), last, "the main receipt is not on the newest message")
    }

    /// Philip's #bugs (2026-11-18): a room rule "notify" counts every event, and a reaction's
    /// redaction after the last message stayed counted, because no timeline shows it. Read to
    /// the end, the room's count on the server is 0.
    func testHiddenEventsAfterTheLastMessageAreReadToo() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        // A teardown block, not defer: a failed assertion stops the test with an exception that
        // skips defer, and the rule would stay for every test after.
        let channel = room
        addTeardownBlock { try? me.setRoomRule(channel, notify: nil); me.signOut(); other.signOut() }
        try me.setRoomRule(room, notify: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let before = try other.send("Quittung vorher C \(stamp)", in: room)
        try me.readReceipt(before, in: room, thread: nil)
        let last = try other.send("Quittung letzte C \(stamp)", in: room)
        let reaction = try other.react("👍", to: last, in: room)
        let redaction = try other.redact(reaction, in: room)
        XCTAssertGreaterThan(try me.notificationCount(in: room), 0, "the room rule counts nothing; the test proves nothing")

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "room did not open")
        XCTAssertTrue(waitFor(30) { (try? self.storedReceipt(me.userID, in: room, thread: nil)) == redaction },
                      "the unthreaded receipt is not on the redaction after the last message")
        XCTAssertTrue(waitFor(30) { (try? me.notificationCount(in: room)) == 0 },
                      "the server still counts the room: \((try? me.notificationCount(in: room)) ?? -1), main receipt \((try? self.storedReceipt(me.userID, in: room, thread: "main")) ?? "none"), last \(last), redaction \(redaction)")
    }

    func testOpeningAThreadSendsNoReceiptTheServerRefuses() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let log = try XCTUnwrap(env["IPHONEBLOG_TEST_SYNAPSE_LOG"], "no IPHONEBLOG_TEST_SYNAPSE_LOG")
        let offset = (try? FileManager.default.attributesOfItem(atPath: log)[.size] as? Int) ?? 0
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Quittung Wurzel \(stamp)", in: room)
        _ = try other.send("Quittung Antwort 1 \(stamp)", in: room, thread: root)
        let reply = try other.send("Quittung Antwort 2 \(stamp)", in: room, thread: root)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "thread did not open")
        XCTAssertTrue(waitFor(30) { (try? me.receiptsCover(reply, in: room, thread: root)) == true },
                      "the thread's receipt does not cover its newest reply")
        sleep(3)
        let refused = try refusedReceipts(log, from: offset)
        XCTAssertTrue(refused.isEmpty, "the server refused receipts:\n" + refused.joined(separator: "\n"))
    }

    /// A thread opened on one of its replies instead of its root (a link, a push or a list
    /// that carries the wrong ID): the receipts still name a thread the server knows.
    func testAThreadOpenedOnAReplySendsNoReceiptTheServerRefuses() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let log = try XCTUnwrap(env["IPHONEBLOG_TEST_SYNAPSE_LOG"], "no IPHONEBLOG_TEST_SYNAPSE_LOG")
        let offset = (try? FileManager.default.attributesOfItem(atPath: log)[.size] as? Int) ?? 0
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Quittung Wurzel B \(stamp)", in: room)
        let first = try other.send("Quittung Antwort B1 \(stamp)", in: room, thread: root)
        _ = try other.send("Quittung Antwort B2 \(stamp)", in: room, thread: root)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(first)"])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "thread did not open")
        sleep(8)
        let refused = try refusedReceipts(log, from: offset)
        XCTAssertTrue(refused.isEmpty, "the server refused receipts:\n" + refused.joined(separator: "\n"))
    }

    // MARK: Helpers

    /// The event of this user's m.read receipt in the room, as Synapse stores it: `thread` nil for
    /// the unthreaded one, "main", or a root's ID. From the test server's database, because a
    /// sync's receipt content has one entry per user and event, so a main and an unthreaded
    /// receipt on the same event hide each other there.
    private func storedReceipt(_ user: String, in room: String, thread: String?) throws -> String? {
        let log = try XCTUnwrap(env["IPHONEBLOG_TEST_SYNAPSE_LOG"], "no IPHONEBLOG_TEST_SYNAPSE_LOG")
        let path = (log as NSString).deletingLastPathComponent + "/homeserver.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw XCTSkip("cannot open \(path)")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        let sql = "SELECT event_id FROM receipts_linearized WHERE room_id = ? AND user_id = ? AND receipt_type = 'm.read' AND "
            + (thread == nil ? "thread_id IS NULL" : "thread_id = ?")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, room, -1, transient)
        sqlite3_bind_text(statement, 2, user, -1, transient)
        if let thread { sqlite3_bind_text(statement, 3, thread, -1, transient) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    /// Receipt requests Synapse answered with 400 since `offset` in its access log.
    private func refusedReceipts(_ path: String, from offset: Int) throws -> [String] {
        let handle = try XCTUnwrap(FileHandle(forReadingAtPath: path), "cannot read \(path)")
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").map(String.init)
            .filter { $0.contains("/receipt/") && $0.contains(" 400 \"") }
    }

    private func waitFor(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        repeat {
            if condition() { return true }
            sleep(1)
        } while Date() < until
        return false
    }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }
}
