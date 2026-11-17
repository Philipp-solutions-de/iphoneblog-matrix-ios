import XCTest

/// A tap on a sender in the timeline opens the app's profile sheet (Thorsten, 2026-11-17:
/// "„View Profile" funktioniert nicht"): name, "Kontaktdaten teilen", Blockieren, Melden.
final class ProfileUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingASenderOpensTheProfile() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let stamp = Int(Date().timeIntervalSince1970)
        // The tester first, so the other's message starts a group and shows its avatar.
        try me.send("Vorher \(stamp)", in: room)
        try other.send("Profiltest \(stamp)", in: room)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        // English on purpose: the label Thorsten saw was English.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 120), "channel did not open")
        let message = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Profiltest \(stamp)")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 30), "the other's message did not arrive")
        sleep(2)

        // The newest message sits just above the composer; its avatar is at the row's left,
        // level with the name above the text. Message rows report no frame to XCUITest.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 34, dy: composer.frame.minY - 52)).tap()

        // A room admin (as Thorsten, and the tester who made the test room) first gets Element X's
        // member sheet with removal and ban; its "Profil ansehen" must lead to the profile.
        let name = app.staticTexts[other.userID]
        let viewProfile = app.buttons["Profil ansehen"]
        XCTAssertTrue(name.waitForExistence(timeout: 15) || viewProfile.exists, "a tap on the sender opened nothing")
        XCTAssertFalse(app.buttons["View profile"].exists || app.buttons["View Profile"].exists, "the sheet is still English")
        if viewProfile.exists {
            save(app, "member-sheet")
            viewProfile.tap()
            XCTAssertTrue(name.waitForExistence(timeout: 15), "\"Profil ansehen\" opened no profile")
        }
        XCTAssertTrue(app.buttons["profile.block"].exists, "no Blockieren")
        XCTAssertTrue(app.buttons["profile.report"].exists, "no Melden")
        save(app, "profile-from-timeline")

        // Melden reaches the server (the report endpoint answers).
        app.buttons["profile.report"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "no report dialog")
        alert.textFields.firstMatch.typeText("UI-Test")
        alert.buttons.matching(NSPredicate(format: "label == %@", "Melden")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Danke. Das Team sieht sich die Meldung an."].waitForExistence(timeout: 15), "the report failed")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
