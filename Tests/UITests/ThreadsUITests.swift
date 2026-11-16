import XCTest

/// Threads in #one-Chat, Slack's way: the row under a message with replies, a tap on a message
/// opens its thread, and "Threads" at the top lists yours. scripts/test-homeserver.sh seeds the
/// thread under "Hat jemand schon das neue iPad mini im Alltag?" with six replies from three
/// people, one of them the tester.
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
        func visible() -> Bool {
            guard target.exists else { return false }
            let frame = target.frame, window = app.windows.firstMatch.frame
            return frame.minY > window.minY + 160 && frame.maxY < window.maxY - 180
        }
        for _ in 0..<20 where !visible() {
            app.swipeDown(velocity: .slow)
            sleep(1) // older messages page in
        }
    }

    func testThreadRowShowsCountAndOpensTheThread() throws {
        let app = try openChannel()
        // Six seeded replies; RichMessagesUITests may have added a photo before this runs.
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label MATCHES '.*[67] Antworten.*'")).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.exists, "no thread row with 6 or 7 Antworten")
        sleep(2) // repliers load
        attach(app, "channel-thread-row")
        row.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "thread did not open")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '[67] Antworten'")).firstMatch.exists,
                      "no count under the root")
        attach(app, "thread-view")
    }

    func testTapOnMessageOpensItsThread() throws {
        let app = try openChannel()
        let message = app.otherElements.matching(NSPredicate(format: "label == 'Nachricht 5 im vollen Kanal'")).firstMatch
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
        let app = try openChannel(inRoom: false)
        let entry = app.buttons["threads-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 120), "no Threads row")
        entry.tap()
        XCTAssertTrue(element(app, containing: "iPad mini").waitForExistence(timeout: 30), "your thread is not listed")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '[67] Antworten'")).firstMatch
            .waitForExistence(timeout: 15), "the list shows the wrong count")
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
