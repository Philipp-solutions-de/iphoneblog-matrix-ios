import XCTest

/// Before someone's first post, once: who will see it, with "Verstanden". Ben (a #one member
/// who has not read it yet) sends twice; the notice comes only before the first.
final class PostingNoticeUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testNoticeBeforeTheFirstPostOnly() throws {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER3"],
              let password = env["IPHONEBLOG_TEST_PASSWORD3"], let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"] else {
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
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 120), "channel did not open")

        composer.tap()
        composer.typeText("Mein erster Beitrag")
        app.buttons["room-send_button"].tap()
        let ok = app.buttons["posting-notice.ok"]
        XCTAssertTrue(ok.waitForExistence(timeout: 20), "no notice before the first post")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'öffentlich auf iphoneblog.de'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "posting-notice"
        shot.lifetime = .keepAlways
        add(shot)
        ok.tap()
        let first = app.textViews.matching(NSPredicate(format: "value CONTAINS 'Mein erster Beitrag'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "the first post was not sent after Verstanden")

        composer.tap()
        composer.typeText("Und noch einer")
        app.buttons["room-send_button"].tap()
        XCTAssertFalse(ok.waitForExistence(timeout: 4), "the notice came again")
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS 'Und noch einer'")).firstMatch.waitForExistence(timeout: 20))
    }
}
