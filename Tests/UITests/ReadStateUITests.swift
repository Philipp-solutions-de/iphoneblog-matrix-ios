import XCTest

/// "Wenn ich eine Erwähnung oder einen Thread lese, muss er auf gelesen gehen" (Thorsten,
/// 2026-11-17), with Matrix's "read up to here" (his decision A): a receipt marks every mention
/// up to it read on the server, the one truth the app and the web share. Each test writes its
/// own messages as another member, so the seeded ones stay as they are.
final class ReadStateUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var room: String { env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
    }

    // 1) @Mentions → a mention in a thread → back: read, the badge one lower. 4) Still read after a relaunch.
    func testThreadMentionTurnsReadAndStaysRead() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Lesetest Wurzel \(stamp)", in: room)
        let mention = try other.send("Lesetest Thread \(stamp)", in: room, mention: me.userID, thread: root)

        var app = launch(tab: "mentions")
        let row = self.row(app, "Lesetest Thread \(stamp)")
        XCTAssertTrue(row.waitForExistence(timeout: 120), "the mention is not in @Mentions")
        XCTAssertTrue(row.label.contains("ungelesen"), "the mention is not unread to start with")
        let before = try XCTUnwrap(mentionsBadge(app))
        row.tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 30), "the thread did not open")
        sleep(2)
        app.tabBars.buttons["Für dich"].tap()
        XCTAssertTrue(waitUntilRead(row), "the row is still unread after reading the thread")
        XCTAssertTrue(waitForBadge(app, atMost: before - 1), "the badge did not drop")
        XCTAssertTrue(try waitForReceipts(me, mention, thread: root), "no receipt of this account covers it (the web would show it unread)")

        app.terminate()
        app = launch(tab: "mentions")
        let again = self.row(app, "Lesetest Thread \(stamp)")
        XCTAssertTrue(again.waitForExistence(timeout: 120), "the mention left @Mentions")
        sleep(3)
        XCTAssertFalse(again.label.contains("ungelesen"), "unread again after a relaunch")
    }

    // 2) @Mentions → a mention in the room's own timeline → back: read, on the server too (so
    // the web shows it read). 4) Still read after a relaunch.
    func testRoomMentionTurnsReadAndStaysRead() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        // As after "Alle als gelesen": an unthreaded receipt in the room, which made Synapse
        // ignore every later "main" receipt (Thorsten's account; ChatSession.sendUnthreadedReceipt).
        let earlier = try other.send("Vorher \(stamp)", in: room)
        try me.readReceipt(earlier, in: room, thread: nil)
        let mention = try other.send("Lesetest Raum \(stamp)", in: room, mention: me.userID)

        var app = launch(tab: "mentions")
        let row = self.row(app, "Lesetest Raum \(stamp)")
        XCTAssertTrue(row.waitForExistence(timeout: 120), "the mention is not in @Mentions")
        XCTAssertTrue(row.label.contains("ungelesen"), "the mention is not unread to start with")
        let before = try XCTUnwrap(mentionsBadge(app))
        row.tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 30), "the room did not open")
        sleep(2) // longer than the dwell
        app.tabBars.buttons["Für dich"].tap()
        XCTAssertTrue(waitUntilRead(row), "the row is still unread after reading it in the room")
        XCTAssertTrue(waitForBadge(app, atMost: before - 1), "the badge did not drop")
        XCTAssertTrue(try waitForReceipts(me, mention, thread: nil), "no receipt of this account covers it (the web would show it unread)")

        app.terminate()
        app = launch(tab: "mentions")
        let again = self.row(app, "Lesetest Raum \(stamp)")
        XCTAssertTrue(again.waitForExistence(timeout: 120), "the mention left @Mentions")
        sleep(3)
        XCTAssertFalse(again.label.contains("ungelesen"), "unread again after a relaunch")
    }

    // 5) The other way round: read elsewhere (a second client) → the iPhone clears both kinds.
    func testReadElsewhereClearsOnTheIPhone() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Anderswo Wurzel \(stamp)", in: room)
        let inThread = try other.send("Anderswo Thread \(stamp)", in: room, mention: me.userID, thread: root)
        let inRoom = try other.send("Anderswo Raum \(stamp)", in: room, mention: me.userID)

        let app = launch(tab: "mentions")
        let threadRow = row(app, "Anderswo Thread \(stamp)"), roomRow = row(app, "Anderswo Raum \(stamp)")
        XCTAssertTrue(threadRow.waitForExistence(timeout: 120) && roomRow.waitForExistence(timeout: 30), "mentions missing")
        XCTAssertTrue(threadRow.label.contains("ungelesen") && roomRow.label.contains("ungelesen"), "not unread to start with")

        // The web chat reads both: the thread's receipt; for the room, "main" and, against the
        // Synapse bug (ChatSession.sendUnthreadedReceipt), unthreaded too.
        try me.readReceipt(inThread, in: room, thread: root)
        try me.readReceipt(inRoom, in: room, thread: "main")
        try me.readReceipt(inRoom, in: room, thread: nil)
        // Sync brings it; the list reloads whenever it is shown.
        app.tabBars.buttons["Ich"].tap()
        app.tabBars.buttons["Für dich"].tap()
        XCTAssertTrue(waitUntilRead(threadRow), "a thread read elsewhere is still unread here")
        XCTAssertTrue(waitUntilRead(roomRow), "a room mention read elsewhere is still unread here")
    }

    // 6) A mention newer than what was seen stays unread: the room was read, then the person
    // went to another tab, then the mention came.
    func testAMentionAfterReadingStaysUnread() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let app = launch(tab: "chat", room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        sleep(3)
        app.tabBars.buttons["Ich"].tap()
        sleep(1)
        let mention = try other.send("Danach \(stamp)", in: room, mention: me.userID)
        sleep(5) // sync brings it; the room's timeline is not on screen
        app.tabBars.buttons["Für dich"].tap()
        let row = self.row(app, "Danach \(stamp)")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the mention is not in @Mentions")
        sleep(2)
        XCTAssertTrue(row.label.contains("ungelesen"), "a mention that came after reading turned read")
        XCTAssertFalse(try me.receiptsCover(mention, in: room, thread: nil), "a receipt covers it although it came after")
    }

    // 3) Threads → a thread with new replies → back: read, the Threads count one lower.
    func testThreadsListClearsWhenAThreadIsRead() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try me.send("Mein Thread \(stamp)", in: room)
        try other.send("Neue Antwort eins", in: room, thread: root)
        try other.send("Neue Antwort zwei", in: room, thread: root)

        let app = launch(tab: "chat")
        let entry = app.buttons["threads-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 120), "no Threads row")
        let unreadBefore = waitForThreadsCount(entry, atLeast: 1)
        XCTAssertGreaterThanOrEqual(unreadBefore, 1, "the Threads row shows no new threads")
        entry.tap()
        let threadRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mein Thread \(stamp)")).firstMatch
        XCTAssertTrue(threadRow.waitForExistence(timeout: 30), "the thread is not in the Threads list")
        threadRow.tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 30), "the thread did not open")
        sleep(2)
        goBack(app)
        XCTAssertTrue(threadRow.waitForExistence(timeout: 10), "back did not return to the Threads list")
        let read = NSPredicate(format: "NOT (label CONTAINS 'ungelesen')")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: read, evaluatedWith: threadRow)], timeout: 10), .completed,
                       "the thread is still marked new")
        goBack(app)
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "back did not return to the rooms")
        XCTAssertEqual(threadsCount(entry), unreadBefore - 1, "the Threads count did not drop by one")
    }

    /// "Alle als gelesen" (build 133 did nothing for thread replies): mentions in the timelines
    /// and in threads of both #one rooms → badge 0, no dot, still so after a relaunch, and the
    /// server (which the web reads) has them read.
    func testAlleAlsGelesenClearsTimelinesAndThreads() throws {
        let (me, other) = try accounts()
        defer { me.signOut(); other.signOut() }
        let room2 = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 }, "no second room")
        try other.join(room2)
        let stamp = Int(Date().timeIntervalSince1970)
        var mentions: [(String, String?)] = []
        for target in [room, room2] {
            // As on Thorsten's account: an unthreaded receipt from an earlier "Alle als gelesen".
            let earlier = try other.send("Früher \(stamp)", in: target)
            try me.readReceipt(earlier, in: target, thread: nil)
            let root = try other.send("Alle Wurzel \(stamp)", in: target)
            mentions.append((try other.send("Alle Zeitleiste \(stamp)", in: target, mention: me.userID), nil))
            mentions.append((try other.send("Alle Thread \(stamp)", in: target, mention: me.userID, thread: root), root))
        }

        var app = launch(tab: "mentions")
        let threadRow = row(app, "Alle Thread \(stamp)")
        XCTAssertTrue(threadRow.waitForExistence(timeout: 120), "the mentions are not listed")
        sleep(3)
        let button = app.buttons["foryou.markAllRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no Alle als gelesen")
        button.tap()
        let anyUnread = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'ungelesen'")).firstMatch
        XCTAssertTrue(anyUnread.waitForNonExistence(timeout: 20), "a row still has its dot")
        XCTAssertTrue(waitForBadge(app, atMost: 0), "the badge is not 0")
        for (index, mention) in mentions.enumerated() {
            let target = index < 2 ? room : room2
            XCTAssertTrue(try waitForReceipts(me, mention.0, in: target, thread: mention.1), "no receipt covers a mention (the web would show it unread)")
        }

        app.terminate()
        app = launch(tab: "mentions")
        XCTAssertTrue(row(app, "Alle Thread \(stamp)").waitForExistence(timeout: 120), "the mentions left the list")
        sleep(4)
        XCTAssertFalse(anyUnread.exists, "a dot is back after a relaunch")
        XCTAssertTrue(waitForBadge(app, atMost: 0), "the badge is back after a relaunch")
    }

    // MARK: - Helpers

    private func accounts() throws -> (TestServer, TestServer) {
        (try TestServer.signIn(1), try TestServer.signIn(2))
    }

    private func launch(tab: String, room: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": tab, "IPHONEBLOG_EXPOSE_BADGES": "1",
            "IPHONEBLOG_START_ROOM": room ?? "",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    /// Back, as a person does it: the swipe from the screen's left edge.
    private func goBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        sleep(1)
    }

    private func row(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func waitUntilRead(_ row: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let read = NSPredicate(format: "exists == true AND NOT (label CONTAINS 'ungelesen')")
        return XCTWaiter.wait(for: [expectation(for: read, evaluatedWith: row)], timeout: timeout) == .completed
    }

    private func mentionsBadge(_ app: XCUIApplication) -> Int? {
        let label = app.descendants(matching: .any)["debug.badges"].label
        guard let part = label.split(separator: " ").first(where: { $0.hasPrefix("foryou=") }) else { return nil }
        return Int(part.dropFirst("foryou=".count))
    }

    private func waitForBadge(_ app: XCUIApplication, atMost value: Int) -> Bool {
        for _ in 0..<20 {
            if let badge = mentionsBadge(app), badge <= value { return true }
            sleep(1)
        }
        return false
    }

    private func threadsCount(_ entry: XCUIElement) -> Int {
        guard let match = entry.label.range(of: #"\d+(?= ungelesen)"#, options: .regularExpression) else { return 0 }
        return Int(entry.label[match]) ?? 0
    }

    private func waitForThreadsCount(_ entry: XCUIElement, atLeast: Int) -> Int {
        for _ in 0..<30 {
            let count = threadsCount(entry)
            if count >= atLeast { return count }
            sleep(1)
        }
        return threadsCount(entry)
    }

    private func waitForReceipts(_ me: TestServer, _ eventID: String, in target: String? = nil, thread: String?) throws -> Bool {
        for _ in 0..<20 {
            if try me.receiptsCover(eventID, in: target ?? room, thread: thread) { return true }
            sleep(1)
        }
        return false
    }

    private func waitForServer(_ me: TestServer, _ eventID: String, read: Bool) throws -> Bool? {
        var last: Bool?
        for _ in 0..<20 {
            last = try me.mentionIsRead(eventID)
            if last == read { return last }
            sleep(1)
        }
        return last
    }
}
