import XCTest

/// App Review's items in the running app, against scripts/test-homeserver.sh: Ich holds the
/// blocked list, the moderation contact and "Konto löschen", and the push primer asks on
/// #one instead of at sign-in. "Melden" on a message is ReportUITests.
final class ModerationUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String: String], arguments: [String] = []) throws -> XCUIApplication {
        guard let url = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_HOMESERVER": url,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + arguments
        app.launch()
        return app
    }

    /// Ich: the blocked list opens (empty for the test user), the moderation contact and
    /// "Konto löschen" are there, and the deletion screen says what goes before it opens the page.
    func testIchHasBlockedListContactAndDeletion() throws {
        let app = try launch(["IPHONEBLOG_START_TAB": "me"])
        XCTAssertTrue(app.buttons["me.blocked"].waitForExistence(timeout: 120), "no Blockiert row")
        XCTAssertTrue(app.buttons["me.moderation"].exists, "no moderation contact")
        app.buttons["me.blocked"].tap()
        XCTAssertTrue(app.staticTexts["Du hast niemanden blockiert."].waitForExistence(timeout: 20))
        app.buttons["Fertig"].tap()
        app.buttons["me.deleteAccount"].tap()
        XCTAssertTrue(app.buttons["me.deleteAccount.continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'keine Erstattung'")).firstMatch.exists)
        attach(app, "delete-explained")
        app.buttons["Abbrechen"].tap()
    }

    /// No system prompt after sign-in; on #one the primer card, and "Später" puts it away.
    func testPushPrimerOnOneChat() throws {
        // "-pushPrimerShown NO" resets the card's flag for this launch (the argument domain wins
        // over the stored value), so an earlier run's "Später" does not hide it.
        let app = try launch(["IPHONEBLOG_START_TAB": "chat"], arguments: ["-pushPrimerShown", "NO"])
        let later = app.buttons["Später"]
        XCTAssertTrue(later.waitForExistence(timeout: 120), "no primer on #one")
        attach(app, "push-primer")
        later.tap()
        XCTAssertFalse(later.waitForExistence(timeout: 3), "primer still there")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
