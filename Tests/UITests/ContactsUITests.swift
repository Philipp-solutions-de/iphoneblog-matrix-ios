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

    /// "Kontaktdaten teilen" from a person's profile: choose, type the number, confirm by name.
    /// The local test server has no such endpoint, so the app's stub answers (the contract's
    /// requests are unit-tested in ContactShareTests).
    func testSharesContactDetailsWithAnotherMember() throws {
        let other = try TestServer.signIn(2)
        other.signOut()
        let app = try launch(["IPHONEBLOG_CONTACT_SHARE_STUB": "1", "IPHONEBLOG_START_PROFILE": other.userID])
        let share = app.buttons["profile.shareContact"]
        XCTAssertTrue(share.waitForExistence(timeout: 120), "no \"Kontaktdaten teilen\" on another member's profile")
        save(app, "profile")
        share.tap()

        XCTAssertTrue(app.descendants(matching: .any)["contactShare.recipient"].waitForExistence(timeout: 20),
                      "the share screen did not open")
        let send = app.buttons["contactShare.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "no send button")
        XCTAssertFalse(send.isEnabled, "sending is possible before anything is chosen")
        XCTAssertTrue(app.staticTexts["tester@example.org"].waitForExistence(timeout: 10), "the own address is not shown")

        // Under load a tap can land before the screen takes it: tap again when nothing happened.
        let number = app.textFields["contactShare.phoneNumber"]
        for _ in 0..<3 where !number.exists {
            tapSwitch(app.switches["contactShare.phone"])
            _ = number.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(number.exists, "no field for the phone number")
        XCTAssertFalse(send.isEnabled, "sending is possible without a number")
        for _ in 0..<3 where !hasFocus(number) {
            number.tap()
            sleep(1)
        }
        number.typeText("0170 1234567")
        XCTAssertTrue(send.isEnabled, "a valid number does not enable sending")
        save(app, "share")

        send.tap()
        let confirm = app.alerts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kontaktdaten an")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no confirmation naming the recipient")
        XCTAssertTrue(confirm.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0170 1234567")).firstMatch.exists,
                      "the confirmation does not show the number")
        save(app, "share-confirm")
        confirm.buttons["Senden"].tap()
        let notice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Kontaktdaten an", "gesendet.")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "no notice after sending")
    }

    /// One's own profile offers no sharing.
    func testOwnProfileOffersNoSharing() throws {
        let me = try TestServer.signIn(1)
        me.signOut()
        let app = try launch(["IPHONEBLOG_CONTACT_SHARE_STUB": "1", "IPHONEBLOG_START_PROFILE": me.userID])
        XCTAssertTrue(app.staticTexts[me.userID].waitForExistence(timeout: 120), "the own profile did not open")
        XCTAssertFalse(app.buttons["profile.shareContact"].exists, "sharing offered with oneself")
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no switch \(toggle)")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func launch(_ extra: [String: String]) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_HOMESERVER": server, "IPHONEBLOG_DEV_USER": user, "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
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
