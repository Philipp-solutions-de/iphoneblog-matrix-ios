import XCTest

/// Swipes on a message: right opens its thread, left the menu with its reactions; inside a
/// thread a swipe from the screen's left edge still goes back.
final class SwipeUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    /// Sends a message of its own and opens the channel on it; returns the app and the row's text.
    /// Other tests leave GIFs and photos at the channel's end, so the screen's middle may fall
    /// between two pictures (2026-11-20): the swipe goes along this message instead.
    private func openChannel(text given: String? = nil) throws -> (XCUIApplication, XCUIElement) {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"], let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let text = given ?? "Swipe \(Int(Date().timeIntervalSince1970))"
        let me = try TestServer.signIn(1)
        defer { me.signOut() }
        _ = try me.send(text, in: room)
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
        // The row's label holds sender, time and text together.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the test's own message is not in the channel")
        sleep(2)
        return (app, row)
    }

    /// A drag that starts on the message itself, `from` across its width, and moves `by` a share
    /// of the screen's width.
    private func swipe(_ app: XCUIApplication, on row: XCUIElement, from: CGFloat, by: CGFloat) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: app.frame.width * by, dy: 0)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
    }

    func testSwipeRightOpensTheThread() throws {
        let (app, row) = try openChannel()
        swipe(app, on: row, from: 0.3, by: 0.6)
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 20), "swipe right did not open the thread")

        // Swipe-back from the screen's edge still leaves the thread.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.textViews["Antworten…"].waitForNonExistence(timeout: 10), "swipe-back from the edge did not leave the thread")
    }

    func testSwipeLeftOffersReactions() throws {
        let (app, row) = try openChannel()
        swipe(app, on: row, from: 0.9, by: -0.6)
        let reaction = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reaktion' OR label CONTAINS '👍'")).firstMatch
        XCTAssertTrue(reaction.waitForExistence(timeout: 20), "swipe left did not offer reactions")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "swipe-left-menu"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The whole row takes the swipe, also the empty space beside a short message (approved
    /// 2026-11-20); a tap there still does nothing.
    func testSwipeLeftFromBesideAShortMessage() throws {
        let short = "ok \(Int(Date().timeIntervalSince1970) % 1000)"
        let (app, row) = try openChannel(text: short)
        // Well to the right of the message's end, on its line.
        let beside = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.85, dy: row.frame.midY))
        // The row spans the width now; the text itself ends well before the swipe's start.
        let words = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", short)).firstMatch
        if words.exists {
            XCTAssertGreaterThan(app.frame.width * 0.85, words.frame.maxX + 40, "the message is not short enough to leave space beside it")
        }

        beside.tap()
        XCTAssertFalse(app.textViews["Antworten…"].waitForExistence(timeout: 3), "a tap beside the message opened its thread")

        beside.press(forDuration: 0.05, thenDragTo: beside.withOffset(CGVector(dx: -app.frame.width * 0.6, dy: 0)),
                     withVelocity: .fast, thenHoldForDuration: 0.05)
        let reaction = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reaktion' OR label CONTAINS '👍'")).firstMatch
        XCTAssertTrue(reaction.waitForExistence(timeout: 20), "a swipe beside a short message offered no reactions")
    }
}
