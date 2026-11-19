import XCTest

/// The four-tab layout (Thorsten, 2026-11-17): #one with its room bar (variant A), Für dich,
/// the Neu divider and the bot badge. Each test writes its own messages as another member.
final class FourTabsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var room: String { env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
        // The previous test's app still runs until the next launch. With the channel open it
        // reads what a test sends before launching, and the badge counts one short.
        XCUIApplication().terminate()
    }

    // MARK: #one

    /// A tap on a room's chip opens that room; nothing else changes rooms.
    func testRoomBarSwitchesByTap() throws {
        let app = launch(tab: "chat", room: room)
        let chips = app.buttons.matching(identifier: "one-room")
        XCTAssertTrue(chips.element(boundBy: 1).waitForExistence(timeout: 120), "fewer than two rooms in the bar")
        let raum2 = chips.matching(NSPredicate(format: "label CONTAINS 'Raum 2'")).firstMatch
        raum2.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Raum 2"].waitForExistence(timeout: 60), "Raum 2 did not open")
        XCTAssertTrue(raum2.isSelected, "the chip of the open room is not marked")
        save(app, "room-bar")
        // The tab opens the last room read.
        app.terminate()
        let again = launch(tab: "chat")
        XCTAssertTrue(again.textViews["Nachricht an # Raum 2"].waitForExistence(timeout: 120), "the tab did not open the last room read")
    }

    /// The open room has nothing new, another one has: "Weiter" leads there.
    func testWeiterLeadsToTheNextRoomWithNews() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room2 = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 })
        try other.join(room2)
        let app = launch(tab: "chat", room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        sleep(3) // read up to here
        try other.send("Weitertest \(Int(Date().timeIntervalSince1970))", in: room2)
        let next = app.buttons["one.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "no Weiter")
        XCTAssertTrue(next.label.contains("Raum 2"), next.label)
        save(app, "weiter")
        next.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Raum 2"].waitForExistence(timeout: 60), "Weiter did not open Raum 2")
    }

    /// More rooms than fit: a room with news out of sight leaves a dot at the edge.
    func testDotForANewsRoomOutOfSight() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let space = try me.resolve(env["IPHONEBLOG_ONE_ALIAS"] ?? "#one:localhost")
        var last = ""
        for (n, name) in ["Entertainment und Kultur", "Technik und Zubehör", "Market und Kleinanzeigen"].enumerated() {
            let id = try me.createRoom(name)
            try me.addChild(id, toSpace: space, order: "z\(n)")
            sleep(1) // Synapse limits how fast rooms are made
            last = id
        }
        // The tester has written there (as one does), so what comes after counts as new.
        try me.send("Hallo", in: last)
        try other.join(last)
        try other.send("Ganz hinten \(Int(Date().timeIntervalSince1970))", in: last)
        let app = launch(tab: "chat", room: room)
        XCTAssertTrue(app.buttons.matching(identifier: "one-room").element(boundBy: 4).waitForExistence(timeout: 120), "the new rooms are not in the bar")
        let dot = app.descendants(matching: .any)["one.roomBar.moreNews"]
        if !dot.waitForExistence(timeout: 30) { save(app, "debug-dot") }
        XCTAssertTrue(dot.exists, "no dot for the room with news out of sight")
        save(app, "room-bar-dot")
    }

    /// The search looks in every room; the chip narrows it to the open one.
    func testSearchAllRoomsOrThisRoom() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room2 = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 })
        try other.join(room2)
        let word = "Suchwort\(Int(Date().timeIntervalSince1970) % 100000)"
        try other.send("Nur in Raum 2: \(word)", in: room2)
        let app = launch(tab: "chat", room: room)
        XCTAssertTrue(app.buttons["chat-search"].waitForExistence(timeout: 120), "no search")
        app.buttons["chat-search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(word)
        let hit = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'search-hit' AND label CONTAINS %@", word)).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 30), "all rooms: the hit in Raum 2 is missing")
        save(app, "search-all")
        app.buttons["search.scope.room"].tap()
        XCTAssertTrue(hit.waitForNonExistence(timeout: 20), "this room (Allgemein) still shows Raum 2's hit")
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 20))
    }

    /// Many new messages: the Neu divider above the first, and the pill that jumps to it. In a
    /// room of its own: thirty messages in the channel would push the seeded GIF and files out of
    /// sight for the tests that come after (GifUITests, RichMessagesUITests).
    func testNeuDividerAndJumpPill() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let space = try me.resolve(env["IPHONEBLOG_ONE_ALIAS"] ?? "#one:localhost")
        let busy = try me.createRoom("Neutest \(stamp)")
        try me.addChild(busy, toSpace: space, order: "y\(stamp)")
        // The tester has written there, so what comes after counts as new.
        try me.send("Hallo", in: busy)
        try other.join(busy)
        for n in 1...30 { try other.send("Neu \(n) \(stamp)", in: busy) }
        let app = launch(tab: "chat", room: busy)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        let pill = app.buttons["room.jumpToUnread"]
        if !pill.waitForExistence(timeout: 30) { save(app, "debug-jump-pill") }
        XCTAssertTrue(pill.exists, "no pill for the first unread message out of sight")
        XCTAssertTrue(pill.label.contains("neue"), pill.label)
        save(app, "jump-pill")
        pill.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline.readMarker"].waitForExistence(timeout: 20), "no Neu divider")
        save(app, "neu-divider")
    }

    /// A bot listed by the server gets a "Bot" pill; nobody else does.
    func testBotBadgeOnlyForListedBots() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        try other.send("Botnachricht \(Int(Date().timeIntervalSince1970))", in: room)
        let app = launch(tab: "chat", room: room, extra: ["IPHONEBLOG_BOTS": other.userID])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        XCTAssertTrue(app.descendants(matching: .any)["bot-badge"].waitForExistence(timeout: 30), "no Bot pill for a listed bot")
        save(app, "bot-badge")
        app.terminate()
        let plain = launch(tab: "chat", room: room, extra: ["IPHONEBLOG_BOTS": "@nobody:localhost"])
        XCTAssertTrue(plain.buttons["room-send_button"].waitForExistence(timeout: 120))
        sleep(3)
        XCTAssertFalse(plain.descendants(matching: .any)["bot-badge"].exists, "a Bot pill for someone not listed")
    }

    // MARK: Für dich

    /// Alles · Erwähnungen · Threads, the badge, and "Alle gelesen" for exactly the filter.
    func testFuerDichFiltersBadgeAndAlleGelesen() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        // My own message first: sending moves my read receipt, which would read an older mention.
        let root = try me.send("Fd Thread \(stamp)", in: room)
        try other.send("Fd Erwähnung \(stamp)", in: room, mention: me.userID)
        try other.send("Fd Antwort \(stamp)", in: room, thread: root)

        let app = launch(tab: "foryou")
        let mentionRow = row(app, "Fd Erwähnung \(stamp)"), threadRow = row(app, "Fd Thread \(stamp)")
        XCTAssertTrue(mentionRow.waitForExistence(timeout: 120) && threadRow.waitForExistence(timeout: 30), "Alles lacks a mention or a thread")
        XCTAssertTrue(waitForBadge(app, atLeast: 2), "the badge does not count mention and thread: \(badge(app) ?? 0)")
        save(app, "fuer-dich-alles")

        app.segmentedControls.buttons["Erwähnungen"].tap()
        XCTAssertTrue(mentionRow.waitForExistence(timeout: 5))
        XCTAssertFalse(threadRow.exists, "a thread under Erwähnungen")
        app.segmentedControls.buttons["Threads"].tap()
        XCTAssertTrue(threadRow.waitForExistence(timeout: 5))
        XCTAssertFalse(mentionRow.exists, "a mention under Threads")

        // "Alle gelesen" under Threads clears the threads, not the mentions.
        app.buttons["foryou.markAllRead"].tap()
        let read = NSPredicate(format: "NOT (label CONTAINS 'ungelesen')")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: read, evaluatedWith: threadRow)], timeout: 15), .completed, "the thread is still new")
        app.segmentedControls.buttons["Erwähnungen"].tap()
        XCTAssertTrue(mentionRow.label.contains("ungelesen"), "Alle gelesen under Threads cleared a mention")
    }

    /// A long press on the Für dich tab marks everything read.
    func testLongPressOnFuerDichReadsEverything() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        try other.send("Lang \(Int(Date().timeIntervalSince1970))", in: room, mention: me.userID)
        let app = launch(tab: "blog")
        XCTAssertTrue(app.tabBars.buttons["Für dich"].waitForExistence(timeout: 120), "not signed in")
        XCTAssertTrue(waitForBadge(app, above: 0), "nothing unread to start with")
        app.tabBars.buttons["Für dich"].press(forDuration: 1.0)
        XCTAssertTrue(waitForBadge(app, atMost: 0), "the long press did not read everything")
    }

    // MARK: - Helpers

    private func launch(tab: String, room: String? = nil, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": tab, "IPHONEBLOG_EXPOSE_BADGES": "1",
            "IPHONEBLOG_START_ROOM": room ?? "",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func badge(_ app: XCUIApplication) -> Int? {
        let label = app.descendants(matching: .any)["debug.badges"].label
        guard let part = label.split(separator: " ").first(where: { $0.hasPrefix("foryou=") }) else { return nil }
        return Int(part.dropFirst("foryou=".count))
    }

    /// The thread's count reaches the badge a sync after the mention's.
    private func waitForBadge(_ app: XCUIApplication, atLeast value: Int) -> Bool {
        for _ in 0..<20 { if let b = badge(app), b >= value { return true }; sleep(1) }
        return false
    }

    private func waitForBadge(_ app: XCUIApplication, atMost value: Int) -> Bool {
        for _ in 0..<20 { if let b = badge(app), b <= value { return true }; sleep(1) }
        return false
    }

    private func waitForBadge(_ app: XCUIApplication, above value: Int) -> Bool {
        for _ in 0..<30 { if let b = badge(app), b > value { return true }; sleep(1) }
        return false
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let style = env["IPHONEBLOG_SHOTS_STYLE"].map { "-" + $0 } ?? ""
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name)\(style).png"))
    }
}
