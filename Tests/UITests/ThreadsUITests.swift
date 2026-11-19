import XCTest

/// Threads in #one-Chat, Slack's way: the row under a message with replies, a tap on a message
/// opens its thread, and "Threads" at the top lists yours. The tests write their own threads
/// just before, so the messages other tests add never bury them.
final class ThreadsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func openChannel(inRoom: Bool = true) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_START_ROOM": inRoom ? env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" : "",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        if inRoom {
            XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        }
        return app
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls the channel towards older messages until the element is on screen.
    /// On screen means inside the window, below the Threads row and above the composer; the list
    /// keeps rows it has scrolled away, with frames outside.
    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication) {
        // Inside the band between the header and the composer. A target below the band, such
        // as a message just sent, needs a swipe up; one not loaded yet, a swipe down.
        func place() -> Int {
            guard target.exists else { return -1 }
            let frame = target.frame, window = app.windows.firstMatch.frame
            if frame.minY <= window.minY + 160 { return -1 }
            if frame.maxY >= window.maxY - 180 { return 1 }
            return 0
        }
        for _ in 0..<20 {
            switch place() {
            case 0: return
            case 1: app.swipeUp(velocity: .slow)
            default: app.swipeDown(velocity: .slow)
            }
            sleep(1) // older messages page in
        }
    }

    /// A thread with six replies from three people, the tester among them: the row under the
    /// root reads "6 Antworten" and opens the thread, with the count under the root. Its own
    /// thread, written just before, so the messages other tests add never bury it.
    func testThreadRowShowsCountAndOpensTheThread() throws {
        let (root, stamp) = try makeBusyThread()
        _ = root
        let app = try openChannel()
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label CONTAINS '6 Antworten'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no thread row with 6 Antworten")
        sleep(2) // repliers load
        attach(app, "channel-thread-row")
        row.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "thread did not open")
        XCTAssertTrue(element(app, containing: "Viel los \(stamp)").waitForExistence(timeout: 15), "the root is not on top")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '6 Antworten'")).firstMatch.exists,
                      "no count under the root")
        attach(app, "thread-view")
    }

    /// Six replies from three people, the tester's among them, under a root by Anna.
    private func makeBusyThread() throws -> (String, Int) {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        let third = try TestServer.signIn(3)
        defer { me.signOut(); other.signOut(); third.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Viel los \(stamp)", in: room)
        for (n, writer) in [third, me, other, third, me, other].enumerated() {
            try writer.send("Antwort \(n + 1)", in: room, thread: root)
        }
        return (root, stamp)
    }

    /// A thread that already has replies when the room opens reads "3 Antworten", never
    /// "Noch keine Antworten" (Thorsten, 2026-11-17: three repliers over "Noch keine Antworten").
    func testExistingThreadShowsItsCount() throws {
        let other = try TestServer.signIn(2)
        let third = try TestServer.signIn(3)
        defer { other.signOut(); third.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Zähltest \(stamp)", in: room)
        try third.send("Antwort eins", in: room, thread: root)
        try other.send("Antwort zwei", in: room, thread: root)
        try third.send("Antwort drei", in: room, thread: root)

        let app = try openChannel()
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label CONTAINS '3 Antworten'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no thread row reading 3 Antworten")
        sleep(3) // the repliers' fetch lands; the count must stay
        XCTAssertTrue(row.exists, "the count changed after the repliers loaded")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label CONTAINS 'Noch keine Antworten'")).firstMatch.exists,
                       "a thread row reads Noch keine Antworten")
        attach(app, "thread-count")
    }

    /// Sends its own message first: other tests write into the channel, and the seeded ones
    /// scroll out of reach.
    func testTapOnMessageOpensItsThread() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let text = "Tipptest \(Int(Date().timeIntervalSince1970))"
        try other.send(text, in: room)
        // Two more below it, so it sits clear of the composer: the newest row's lower half is
        // where a tap lands on the composer.
        try other.send("Tipptest danach 1", in: room)
        try other.send("Tipptest danach 2", in: room)
        let app = try openChannel()
        let message = app.otherElements.matching(NSPredicate(format: "label == %@", text)).firstMatch
        scrollTo(message, in: app)
        XCTAssertTrue(message.exists, "message not found")
        message.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "a tap did not open the thread")
        sleep(2)
        attach(app, "thread-new")
        add(XCTAttachment(string: app.debugDescription))
        XCTAssertTrue(element(app, containing: "Noch keine Antworten").waitForExistence(timeout: 30),
                      "a new thread should say it has no replies")
    }

    func testThreadsRowListsYourThreads() throws {
        let (_, stamp) = try makeBusyThread()
        let app = try openChannel(inRoom: false)
        XCTAssertTrue(app.tabBars.buttons["Für dich"].waitForExistence(timeout: 120), "not signed in")
        app.tabBars.buttons["Für dich"].tap()
        let threads = app.segmentedControls.buttons["Threads"]
        XCTAssertTrue(threads.waitForExistence(timeout: 30), "no Threads filter in Für dich")
        threads.tap()
        // Newest activity first, so the thread just written is on top.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Viel los \(stamp)")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "your thread is not listed")
        let count = NSPredicate(format: "label CONTAINS '6 Antworten'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: count, evaluatedWith: row)], timeout: 15), .completed,
                       "the list shows the wrong count: \(row.label)")
        attach(app, "threads-list")
    }

    /// #one-Chat lists the #one rooms in order; a tap opens one.
    func testRoomListOpensARoom() throws {
        let app = try openChannel(inRoom: false)
        let rooms = app.buttons.matching(identifier: "one-room")
        XCTAssertTrue(rooms.element(boundBy: 1).waitForExistence(timeout: 120), "fewer than two rooms")
        XCTAssertTrue(rooms.element(boundBy: 0).label.contains("Allgemein"), rooms.element(boundBy: 0).label)
        XCTAssertTrue(rooms.element(boundBy: 1).label.contains("Raum 2"), rooms.element(boundBy: 1).label)
        attach(app, "room-list")
        rooms.element(boundBy: 1).tap()
        XCTAssertTrue(app.textViews["Nachricht an # Raum 2"].waitForExistence(timeout: 60), "Raum 2 did not open")
        attach(app, "room-raum-2")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
