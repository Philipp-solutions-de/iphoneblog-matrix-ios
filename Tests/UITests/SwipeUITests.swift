import XCTest

/// Swipes on a message: right opens its thread, left the menu with its reactions; inside a
/// thread a swipe from the screen's left edge still goes back.
final class SwipeUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func openChannel() throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"], let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": server, "IPHONEBLOG_DEV_USER": user, "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        sleep(3)
        return app
    }

    /// A drag along a message row in the middle of the timeline.
    private func swipe(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        // The middle of the timeline: there is always a message there.
        let y = app.frame.height * 0.5
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * from, dy: y))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * to, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.05)
    }

    func testSwipeRightOpensTheThread() throws {
        let app = try openChannel()
        swipe(app, from: 0.3, to: 0.9)
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 20), "swipe right did not open the thread")

        // Swipe-back from the screen's edge still leaves the thread.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.textViews["Antworten…"].waitForNonExistence(timeout: 10), "swipe-back from the edge did not leave the thread")
    }

    func testSwipeLeftOffersReactions() throws {
        let app = try openChannel()
        swipe(app, from: 0.8, to: 0.2)
        let reaction = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reaktion' OR label CONTAINS '👍'")).firstMatch
        XCTAssertTrue(reaction.waitForExistence(timeout: 20), "swipe left did not offer reactions")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "swipe-left-menu"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
