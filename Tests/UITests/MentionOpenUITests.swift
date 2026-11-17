import XCTest

/// Every @Mentions row opens where it was said (Thorsten, 2026-11-17: rows from another room did
/// nothing): a reply in a thread opens that thread with the reply on screen, a message in a
/// room's timeline opens the room at that message. Here in the second #one room ("Raum 2").
final class MentionOpenUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testMentionsInASecondRoomOpen() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let room2 = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 }, "no second room")
        try other.join(room2)
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Zweiter Raum Wurzel \(stamp)", in: room2)
        try other.send("Zweiter Raum Thread \(stamp)", in: room2, mention: me.userID, thread: root)
        try other.send("Zweiter Raum Zeitleiste \(stamp)", in: room2, mention: me.userID)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "mentions",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        // The thread reply: its thread opens, the reply on screen.
        let threadRow = row(app, "Zweiter Raum Thread \(stamp)")
        XCTAssertTrue(threadRow.waitForExistence(timeout: 120), "the thread mention is not in @Mentions")
        threadRow.tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 30), "a thread mention in another room opened no thread")
        XCTAssertTrue(message(app, "Zweiter Raum Thread \(stamp)").waitForExistence(timeout: 30), "the reply is not on screen")
        save(app, "mention-thread-room2")

        // The timeline message: its room opens at that message.
        app.tabBars.buttons["Für dich"].tap()
        let roomRow = row(app, "Zweiter Raum Zeitleiste \(stamp)")
        XCTAssertTrue(roomRow.waitForExistence(timeout: 30), "the room mention is not in @Mentions")
        roomRow.tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 30), "a room mention in another room opened no room")
        XCTAssertTrue(message(app, "Zweiter Raum Zeitleiste \(stamp)").waitForExistence(timeout: 30), "the message is not on screen")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Raum 2")).firstMatch.exists,
                      "the room is not Raum 2")
        save(app, "mention-room-room2")
    }

    private func row(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func message(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.textViews.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
