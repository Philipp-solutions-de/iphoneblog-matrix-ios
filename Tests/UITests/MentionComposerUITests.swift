import XCTest

/// A mention picked from the composer's list, then text (Alex's message, 2026-11-17): the body
/// goes out plain ("Anna K. Wir könnten …"), the link only in formatted_body, as the spec and the
/// web chat do.
final class MentionComposerUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testPickedMentionGoesOutAsPlainBody() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        sleep(3)

        let composer = app.textViews["room-message_composer"].firstMatch
        composer.tap()
        let localpart = String(other.userID.dropFirst().prefix { $0 != ":" })
        composer.typeText("@\(localpart.prefix(3))")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", localpart)).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 20), "no suggestion for @\(localpart)")
        suggestion.tap()
        let stamp = "Wir könnten \(Int(Date().timeIntervalSince1970))"
        composer.typeText(stamp)
        app.buttons["room-send_button"].tap()

        let content = try XCTUnwrap(me.message(in: room, containing: stamp), "the message did not arrive")
        let body = content["body"] as? String ?? ""
        let html = content["formatted_body"] as? String ?? ""
        XCTAssertFalse(body.contains("matrix.to"), "the mention went out as a link in body: \(body)")
        XCTAssertFalse(body.contains("]("), "the mention went out as markdown in body: \(body)")
        XCTAssertTrue(html.contains("https://matrix.to/#/\(other.userID)") || html.contains("https://matrix.to/#/%40"),
                      "formatted_body has no mention link: \(html)")
        XCTAssertEqual((content["m.mentions"] as? [String: Any])?["user_ids"] as? [String], [other.userID], "no m.mentions")
    }
}
