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

    private func openChannel() throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
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
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label CONTAINS '6 Antworten'")).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.exists, "no thread row with 6 Antworten")
        sleep(2) // repliers load
        attach(app, "channel-thread-row")
        row.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "thread did not open")
        XCTAssertTrue(element(app, containing: "6 Antworten").exists, "no count under the root")
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
        XCTAssertTrue(element(app, containing: "Noch keine Antworten").exists, "a new thread should say it has no replies")
    }

    func testThreadsRowListsYourThreads() throws {
        let app = try openChannel()
        let entry = app.buttons["threads-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "no Threads row")
        entry.tap()
        XCTAssertTrue(element(app, containing: "iPad mini").waitForExistence(timeout: 30), "your thread is not listed")
        XCTAssertTrue(element(app, containing: "6 Antworten").waitForExistence(timeout: 15), "the list shows the wrong count")
        attach(app, "threads-list")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
