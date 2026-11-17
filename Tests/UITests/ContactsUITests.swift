import XCTest

/// Contact details (Thorsten, 2026-11-17): a message with a phone number or an email address asks
/// first, since the whole room reads it.
final class ContactsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testWarnsBeforeSendingContactDetails() throws {
        let app = try launchInRoom()
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        let stamp = "Test \(Int(Date().timeIntervalSince1970))"
        let body = "Erreichbar unter 0170 1234567, \(stamp)"
        composer.tap()
        composer.typeText(body)

        // Abbrechen: nothing goes out, the text stays to be changed.
        app.buttons["room-send_button"].tap()
        XCTAssertTrue(app.alerts["Kontaktdaten senden?"].waitForExistence(timeout: 10), "no warning before sending a phone number")
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0170 1234567")).firstMatch.exists,
                      "the warning does not name the number")
        save(app, "contact-warning")
        app.alerts.buttons["Abbrechen"].tap()
        // The composer holds the same text; a sent message is any other text view with it.
        let sent = app.textViews.matching(NSPredicate(format: "value CONTAINS %@ AND identifier != %@", stamp, "room-message_composer")).firstMatch
        sleep(3)
        XCTAssertEqual((composer.value as? String) ?? "", body, "Abbrechen lost the text")
        XCTAssertFalse(sent.exists, "the message went out after Abbrechen")

        // Trotzdem senden: it goes out as written.
        app.buttons["room-send_button"].tap()
        XCTAssertTrue(app.alerts["Kontaktdaten senden?"].waitForExistence(timeout: 10), "no warning the second time")
        app.alerts.buttons["Trotzdem senden"].tap()
        XCTAssertTrue(sent.waitForExistence(timeout: 30), "the message did not go out after Trotzdem senden")
        XCTAssertFalse((composer.value as? String ?? "").contains(stamp), "the composer kept the sent text")
    }

    // MARK: - Helpers

    private func launchInRoom() throws -> XCUIApplication {
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

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
