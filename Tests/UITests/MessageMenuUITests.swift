import XCTest

/// A message's menu is German on an English iPhone, has no "Translate", and "Text auswählen"
/// shows the text in a sheet where part of it can be selected.
final class MessageMenuUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testMenuIsGermanAndSelectsText() throws {
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
        // English on purpose: Alex's iPhone is English, and the menu must still be German.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        sleep(3)

        // A text message of its own, so the menu belongs to text, then a long press on it.
        let body = "Menütest \(Int(Date().timeIntervalSince1970))"
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        composer.tap()
        composer.typeText(body)
        app.buttons["room-send_button"].tap()
        let sent = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", body)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 30), "the test message did not appear")
        sleep(2)
        // Message text reports no frame to XCUITest; the newest message sits just above the
        // composer, so the long press goes there.
        let above = composer.frame.minY - 24
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.4, dy: above))
            .press(forDuration: 1.2)

        let select = app.buttons["Text auswählen"]
        XCTAssertTrue(select.waitForExistence(timeout: 20), "no \"Text auswählen\" in the menu")
        for label in ["Im Thread antworten", "Link kopieren", "Text kopieren"] {
            XCTAssertTrue(app.buttons[label].exists, "menu lacks \"\(label)\"")
        }
        for label in ["Translate", "Übersetzen", "Reply", "Copy text", "Copy link"] {
            XCTAssertFalse(app.buttons[label].exists, "menu still shows \"\(label)\"")
        }
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "message-menu"
        menu.lifetime = .keepAlways
        add(menu)
        save(app, "message-menu")

        select.tap()
        let text = app.textViews["text-selection.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the selection sheet did not open")
        XCTAssertFalse((text.value as? String ?? "").isEmpty, "the selection sheet shows no text")
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "text-selection"
        sheet.lifetime = .keepAlways
        add(sheet)
        save(app, "text-selection")

        app.buttons["text-selection.done"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 10), "\"Fertig\" did not close the sheet")
    }

    /// "Link kopieren" copies a readable link on chat.iphoneblog.de, not matrix.to; opened (as iOS
    /// hands over a universal link), a room message's link opens the room, a thread reply's link
    /// its thread.
    func testCopiedLinksAreReadableAndOpenInTheApp() throws {
        let app = try launch()
        let composer = app.textViews["room-message_composer"].firstMatch
        _ = try sendAndLongPress(app, composer: composer, body: "Linktest \(Int(Date().timeIntervalSince1970))")
        let roomLink = try copyLink(app, into: composer)
        save(app, "copied-link")

        // Answer in the message's thread (a tap on it opens the thread), then copy that reply's link.
        composer.clearText()
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.4, dy: composer.frame.minY - 24)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["thread.header"].waitForExistence(timeout: 20), "the message's thread did not open")
        let reply = app.textViews["room-message_composer"].firstMatch
        _ = try sendAndLongPress(app, composer: reply, body: "Antwort \(Int(Date().timeIntervalSince1970))")
        let replyLink = try copyLink(app, into: reply)
        XCTAssertFalse(replyLink.contains("/t/"), "a thread reply's link names its thread: \(replyLink)")

        // The room message's link, from outside: the room, not a thread, not Safari.
        app.terminate()
        let room = try launch(openURL: roomLink, startInRoom: false)
        XCTAssertTrue(room.buttons["room-send_button"].waitForExistence(timeout: 60), "the room did not open")
        sleep(2)
        XCTAssertFalse(room.descendants(matching: .any)["thread.header"].exists, "a room message's link opened a thread")
        XCTAssertTrue(room.buttons["room-send_button"].isHittable, "something covers the room")
        save(room, "link-opened-room")

        // The reply's link: its thread, found from the event itself.
        room.terminate()
        let thread = try launch(openURL: replyLink, startInRoom: false)
        XCTAssertTrue(thread.descendants(matching: .any)["thread.header"].waitForExistence(timeout: 60), "a thread reply's link did not open its thread")
        save(thread, "link-opened-thread")
    }

    /// Copies the message menu's link and pastes it into the composer through the edit menu (the
    /// test runner may not read the app's pasteboard without a prompt); returns it.
    private func copyLink(_ app: XCUIApplication, into composer: XCUIElement) throws -> String {
        let copy = app.buttons["Link kopieren"]
        XCTAssertTrue(copy.waitForExistence(timeout: 20), "no \"Link kopieren\" in the menu")
        copy.tap()
        sleep(1)
        composer.press(forDuration: 1.2)
        let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Einsetzen", "Paste"])).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 10), "no paste in the composer's menu")
        paste.tap()
        let link = composer.value as? String ?? ""
        XCTAssertTrue(link.hasPrefix("https://chat.iphoneblog.de/#/"), "copied link is \(link)")
        XCTAssertTrue(link.contains("/$"), "copied link names no message: \(link)")
        XCTAssertFalse(link.contains("matrix.to"), "copied link is still matrix.to: \(link)")
        return link
    }

    private func launch(openURL: String? = nil, startInRoom: Bool = true) throws -> XCUIApplication {
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
        if !startInRoom { app.launchEnvironment["IPHONEBLOG_START_ROOM"] = nil; app.launchEnvironment["IPHONEBLOG_START_TAB"] = "blog" }
        if let openURL { app.launchEnvironment["IPHONEBLOG_OPEN_URL"] = openURL }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        guard startInRoom else { return app }
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        sleep(3)
        return app
    }

    /// Sends a text message of its own and long-presses it. Message text reports no frame to
    /// XCUITest; the newest message sits just above the composer, so the press goes there.
    private func sendAndLongPress(_ app: XCUIApplication, composer: XCUIElement, body: String) throws -> XCUIElement {
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        composer.tap()
        composer.typeText(body)
        app.buttons["room-send_button"].tap()
        let sent = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", body)).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 30), "the test message did not appear")
        sleep(2)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.4, dy: composer.frame.minY - 24))
            .press(forDuration: 1.2)
        return sent
    }

    /// A passing run drops its attachments; with IPHONEBLOG_SHOTS set (as TEST_RUNNER_…), the
    /// screenshots also land in the runner's temporary folder, under iphoneblog-shots/, where
    /// the simulator's data folder on the Mac holds them.
    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}

private extension XCUIElement {
    /// Empties a text view through its edit menu: "Alles auswählen", then delete.
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        press(forDuration: 1.2)
        let app = XCUIApplication()
        let all = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Alles auswählen", "Select All"])).firstMatch
        if all.waitForExistence(timeout: 5) {
            all.tap()
            typeText(XCUIKeyboardKey.delete.rawValue)
        } else {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
    }
}
