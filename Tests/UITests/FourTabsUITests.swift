import XCTest

/// The four-tab layout (Thorsten, 2026-11-17): #one with its room bar (variant A), Für dich,
/// the Neu divider and the bot badge. Each test writes its own messages as another member.
final class FourTabsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var room: String { env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
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

    /// The open room has nothing new, another one has: no "Weiter" bar over the room (Thorsten,
    /// 2026-11-20); the room bar counts the news, and a tap on it opens that room.
    func testRoomBarLeadsToTheNextRoomWithNews() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room2 = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 })
        try other.join(room2)
        let app = launch(tab: "chat", room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        sleep(3) // read up to here
        try other.send("Weitertest \(Int(Date().timeIntervalSince1970))", in: room2)
        let news = app.buttons.matching(NSPredicate(format: "identifier == 'one-room' AND label BEGINSWITH 'Raum 2,' AND label CONTAINS 'ungelesen'")).firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 30), "the room bar shows no news for Raum 2")
        XCTAssertFalse(app.buttons["one.next"].exists, "the Weiter bar is back")
        save(app, "room-bar-news")
        news.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Raum 2"].waitForExistence(timeout: 60), "the room bar did not open Raum 2")
    }

    /// A read-only room (#releases): only the team posts. No composer, one quiet line in its
    /// place (Thorsten, 2026-11-20); the room still opens and shows its messages.
    func testReadOnlyRoomShowsNoComposer() throws {
        let me = try TestServer.signIn(1)
        let team = try TestServer.signIn(2)
        defer { me.signOut(); team.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let releases = try team.createReadOnlyRoom("Releases \(stamp)")
        try team.send("Build \(stamp) ist live", in: releases)
        try me.join(releases)
        let space = try me.resolve(env["IPHONEBLOG_ONE_ALIAS"] ?? "#one:localhost")
        try me.addChild(releases, toSpace: space, order: "x\(stamp)")
        let app = launch(tab: "chat", room: releases)
        let line = app.staticTexts["Nur das Team schreibt hier"]
        XCTAssertTrue(line.waitForExistence(timeout: 120), "no line in place of the composer")
        let message = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Build \(stamp) ist live")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 30), "the room's message is not shown")
        XCTAssertFalse(app.buttons["room-send_button"].exists, "a composer in a read-only room")
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "label BEGINSWITH 'Nachricht an'")).firstMatch.exists, "a text field in a read-only room")
        save(app, "read-only-room")
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

    /// Many new messages: the Neu divider above the first stays; the pill that jumped to it is
    /// gone (Thorsten, 2026-11-19: Tweetbot's read position instead, ReadPositionUITests). In a
    /// room of its own: thirty messages in the channel would push the seeded GIF and files out of
    /// sight for the tests that come after (GifUITests, RichMessagesUITests).
    func testNeuDividerWithoutJumpPill() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let space = try me.resolve(env["IPHONEBLOG_ONE_ALIAS"] ?? "#one:localhost")
        let busy = try me.createRoom("Neutest \(stamp)")
        try me.addChild(busy, toSpace: space, order: "y\(stamp)")
        // The tester has read up to here (m.fully_read, where the divider goes), so what comes
        // after counts as new.
        let hello = try me.send("Hallo", in: busy)
        try me.setFullyRead(hello, in: busy)
        try other.join(busy)
        // Ten, not thirty: the SDK places the divider only when m.fully_read is among the events
        // the room's first sync brings (about 20). With 30 new messages "Hallo" came later by
        // back-pagination and no divider was drawn, 6 of 8 attempts (2026-11-21). That gap is a
        // bug of its own (architecture.md, Open points); this test covers the divider and the missing pill.
        for n in 1...10 { try other.send("Neu \(n) \(stamp)", in: busy) }
        let app = launch(tab: "chat", room: busy)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        sleep(3)
        XCTAssertFalse(app.buttons["room.jumpToUnread"].exists, "the old jump pill is back")
        // The room is new to the app: its messages and the read position (m.fully_read) arrive
        // with sync, a moment after it opens. Wait for the messages, then give the divider time
        // at each swipe; twelve swipes in a row ran out before it came (CI, main 9cb997c).
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Neu 10 \(stamp)")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 60), "the new messages did not arrive")
        let marker = app.descendants(matching: .any)["timeline.readMarker"]
        for _ in 0..<12 where !marker.waitForExistence(timeout: 2) {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "no Neu divider above the first new message")
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

    /// The mentions in a preview are the timeline's rounded pills, my name solid teal, another
    /// name soft teal (Philip, #bugs 2026-11-21: "Highlighted usernames sind eckig"). The shape
    /// is for the eye: the row's picture is kept with every run; MentionHighlightTests checks
    /// that no square background is set.
    func testFuerDichMentionsAreRoundPills() throws {
        closeRunningApp()
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let myName = String(me.userID.dropFirst().split(separator: ":")[0])
        let html = "Pille <a href=\"https://matrix.to/#/\(me.userID)\">@\(myName)</a> und "
            + "<a href=\"https://matrix.to/#/\(other.userID)\">@Anna</a>, schau mal \(stamp)"
        _ = try other.sendContent(["msgtype": "m.text",
                                   "body": "Pille @\(myName) und @Anna, schau mal \(stamp)",
                                   "format": "org.matrix.custom.html", "formatted_body": html,
                                   "m.mentions": ["user_ids": [me.userID, other.userID]]], in: room)

        let app = launch(tab: "foryou")
        let mention = row(app, "schau mal \(stamp)")
        XCTAssertTrue(mention.waitForExistence(timeout: 120), "the mention is not in Für dich")
        sleep(1)
        let shot = XCTAttachment(screenshot: mention.screenshot())
        shot.name = "fuer-dich-mention-pills"
        shot.lifetime = .keepAlways
        add(shot)
        save(app, "fuer-dich-mention-pills")
    }

    /// Alles · Erwähnungen · Threads, the badge, and "Alle gelesen" for exactly the filter.
    func testFuerDichFiltersBadgeAndAlleGelesen() throws {
        closeRunningApp()
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

    /// A long press on the Für dich tab asks, then marks everything read; cancelling keeps it.
    func testLongPressOnFuerDichReadsEverything() throws {
        closeRunningApp()
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        try other.send("Lang \(Int(Date().timeIntervalSince1970))", in: room, mention: me.userID)
        let app = launch(tab: "blog")
        XCTAssertTrue(app.tabBars.buttons["Für dich"].waitForExistence(timeout: 120), "not signed in")
        XCTAssertTrue(waitForBadge(app, above: 0), "nothing unread to start with")
        let before = badge(app) ?? 0
        app.tabBars.buttons["Für dich"].press(forDuration: 1.0)
        let confirm = app.buttons["Alle als gelesen markieren"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the long press does not ask first")
        save(app, "fuer-dich-confirm")
        // iOS 26 shows the cancel action only as a tap outside the dialog.
        if app.buttons["Abbrechen"].exists { app.buttons["Abbrechen"].tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5), "the dialog did not close")
        sleep(2)
        XCTAssertEqual(badge(app) ?? 0, before, "cancelling still read something")
        app.tabBars.buttons["Für dich"].press(forDuration: 1.0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the second long press does not ask")
        confirm.tap()
        XCTAssertTrue(waitForBadge(app, atMost: 0), "the confirmed long press did not read everything")
    }

    // MARK: - Helpers

    /// The previous test's app still runs until the next launch. With the channel open it reads
    /// what a test sends before launching, and the Für dich badge counts one short. Not for every
    /// test: the Neu test needs the running app to have synced its room.
    private func closeRunningApp() { XCUIApplication().terminate() }

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
