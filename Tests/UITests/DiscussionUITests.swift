import XCTest

/// The way from the blog into an article's discussion and back, driven like a reader does it.
/// scripts/build.sh ui starts scripts/blog-fixture-server.py and passes its address; the member
/// test also needs the test homeserver (scripts/test-homeserver.sh).
final class DiscussionUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8793" }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(member: Bool) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_BLOG_WEB": "\(fixture)/blog/?app=1",
            "IPHONEBLOG_BLOG_API": "\(fixture)/api",
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
        ]
        if member {
            guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
                  let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
                throw XCTSkip("no test homeserver configured")
            }
            app.launchEnvironment.merge([
                "IPHONEBLOG_HOMESERVER": server,
                "IPHONEBLOG_DEV_USER": user,
                "IPHONEBLOG_DEV_PASSWORD": password,
                "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
                "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
                "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
            ]) { _, new in new }
        } else {
            app.launchEnvironment["IPHONEBLOG_SIGNED_OUT"] = "1"
        }
        app.launch()
        return app
    }

    /// Signed out: the discussion of an article that has a thread opens read-only, without
    /// "Artikel lesen", and a swipe from the left edge returns to the blog where it was.
    func testReaderOpensDiscussionAndSwipesBack() throws {
        let app = try launch(member: false)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20), "no blog web view")
        XCTAssertTrue(web.staticTexts["Artikel 1"].waitForExistence(timeout: 20), "blog page not loaded")

        // Down to article 6, well below the first screen, so "the same place" means something.
        let link = web.links["Diskussion 6"]
        for _ in 0..<12 where !link.isHittable { web.swipeUp(velocity: .slow) }
        XCTAssertTrue(link.isHittable, "Diskussion 6 not reached")
        XCTAssertFalse(web.staticTexts["Artikel 1"].isHittable, "the blog did not scroll")
        let heading = web.staticTexts["Artikel 6"]
        let before = heading.frame.minY

        link.tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 15), "discussion did not open")
        XCTAssertTrue(app.staticTexts["Guter Punkt."].waitForExistence(timeout: 15), "replies not shown")
        XCTAssertFalse(app.buttons["Artikel lesen"].exists, "\"Artikel lesen\" is still there")
        attach(app, "reader-thread")

        swipeBackFromLeftEdge(app)
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 5), "swipe did not go back")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertFalse(web.staticTexts["Artikel 1"].isHittable, "the blog went back to the top")
        XCTAssertEqual(heading.frame.minY, before, accuracy: 2, "the blog lost its scroll position")
        attach(app, "reader-after-swipe-back")
    }

    /// Signed out, an article without a thread: no empty screen, an offer to sign in.
    func testReaderWithoutThreadIsOfferedSignIn() throws {
        let app = try launch(member: false)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 3"].waitForExistence(timeout: 20))
        web.links["Diskussion 3"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Antworten"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Anmelden"].exists)
        attach(app, "reader-no-thread")
    }

    /// Signed in: the first tap on an article without a thread has the server make one and
    /// opens it; the second tap opens the same thread without making another.
    func testMemberGetsAThreadMadeOnce() throws {
        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 1"].waitForExistence(timeout: 30))
        // The sign-in runs in the background; the thread needs the session.
        sleep(8)
        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 15))
        // The chat views expose senders, not message text: the bot's root by the test writer, and
        // the composer that answers in the thread.
        XCTAssertTrue(app.staticTexts["Stefan L."].firstMatch.waitForExistence(timeout: 30), "thread not opened")
        XCTAssertTrue(app.buttons["room-send_button"].exists, "no composer")
        attach(app, "member-thread")

        swipeBackFromLeftEdge(app)
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 5), "swipe did not go back")
        attach(app, "member-after-swipe-back")

        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.staticTexts["Stefan L."].firstMatch.waitForExistence(timeout: 30), "second tap: thread not opened")
        let calls = try fixtureCalls()
        XCTAssertEqual(calls["created"], 1, "the server should make the thread once: \(calls)")
    }

    // MARK: Helpers

    private func swipeBackFromLeftEdge(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func fixtureCalls() throws -> [String: Int] {
        let data = try Data(contentsOf: XCTUnwrap(URL(string: "\(fixture)/calls")))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
}
