import XCTest

/// App Review's items in the running app, against scripts/test-homeserver.sh: "Melden" on a
/// message reaches the server (the sheet says thanks only after Synapse answered 200), Ich holds
/// the blocked list, the moderation contact and "Konto löschen", and the push primer asks on
/// #one-Chat instead of at sign-in.
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

    /// Long-press a seeded message, "Melden", a reason, "Senden": the thanks appear only once the
    /// server accepted the report.
    func testReportAMessage() throws {
        let app = try launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? ""])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Lies das'")).firstMatch
        for _ in 0..<8 where !message.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(message.waitForExistence(timeout: 30), "seeded message not found")
        message.press(forDuration: 1.0)
        let report = app.buttons["Melden"]
        XCTAssertTrue(report.waitForExistence(timeout: 10), "no Melden in the menu")
        report.tap()
        XCTAssertTrue(app.buttons["report.send"].waitForExistence(timeout: 10), "report sheet did not open")
        attach(app, "report-sheet")
        app.buttons["report.send"].tap()
        let thanks = app.staticTexts["Danke. Die Moderation schaut es sich an."]
        XCTAssertTrue(thanks.waitForExistence(timeout: 20), "the server did not accept the report")
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

    /// No system prompt after sign-in; on #one-Chat the primer card, and "Später" puts it away.
    func testPushPrimerOnOneChat() throws {
        // "-pushPrimerShown NO" resets the card's flag for this launch (the argument domain wins
        // over the stored value), so an earlier run's "Später" does not hide it.
        let app = try launch(["IPHONEBLOG_START_TAB": "chat"], arguments: ["-pushPrimerShown", "NO"])
        let later = app.buttons["Später"]
        XCTAssertTrue(later.waitForExistence(timeout: 120), "no primer on #one-Chat")
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
