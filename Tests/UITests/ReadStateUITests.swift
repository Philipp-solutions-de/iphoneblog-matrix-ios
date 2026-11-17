import XCTest

/// A mention turns read when it is seen where it was said: opening its thread or its room is
/// enough, without "Alle als gelesen" (Thorsten, 2026-11-17). A thread mention turns read on the
/// server; a room mention in the app's own account data (de.iphoneblog.mentions_seen), because
/// Synapse ignores the room timeline's receipt for its list (MentionsModel.seen). Both leave the
/// list's unread dot.
final class ReadStateUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testOpeningAMentionMarksItRead() throws {
        let other = try TestServer.signIn(2)
        let me = try TestServer.signIn(1)
        defer { other.signOut(); me.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Lesetest Wurzel \(stamp)", in: room)
        let inThread = try other.send("Lesetest Thread \(stamp)", in: room, mention: me.userID, thread: root)
        let inRoom = try other.send("Lesetest Raum \(stamp)", in: room, mention: me.userID)
        XCTAssertEqual(try waitForRead(me, inThread, toBe: false), false, "the thread mention is not unread to start with")

        let app = launch()
        let threadRow = row(app, "Lesetest Thread \(stamp)")
        XCTAssertTrue(threadRow.waitForExistence(timeout: 90), "the thread mention is not in @Mentions")
        XCTAssertTrue(threadRow.label.contains("ungelesen"), "the thread mention is not shown unread: \(threadRow.label)")
        save(app, "mentions-unread")

        // The room mention, seen in its room: read too.
        let roomRow = row(app, "Lesetest Raum \(stamp)")
        XCTAssertTrue(roomRow.waitForExistence(timeout: 30), "the room mention is not in @Mentions")
        roomRow.tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 30), "the room did not open")
        var ids: [String] = []
        for _ in 0..<20 where !ids.contains(inRoom) {
            ids = try me.accountData("de.iphoneblog.mentions_seen")?["ids"] as? [String] ?? []
            if !ids.contains(inRoom) { sleep(1) }
        }
        XCTAssertTrue(ids.contains(inRoom), "opening the room did not mark the mention seen")

        // Its thread, opened and seen: read, without "Alle als gelesen".
        app.tabBars.buttons["@Mentions"].tap()
        XCTAssertTrue(threadRow.waitForExistence(timeout: 30), "the thread mention left @Mentions")
        threadRow.tap()
        XCTAssertTrue(app.staticTexts["Thread"].waitForExistence(timeout: 30), "the thread did not open")
        XCTAssertEqual(try waitForRead(me, inThread, toBe: true), true, "opening the thread did not mark the mention read")
        save(app, "thread-seen")

        // Back in @Mentions, neither row is unread any more.
        app.tabBars.buttons["@Mentions"].tap()
        for text in ["Lesetest Thread \(stamp)", "Lesetest Raum \(stamp)"] {
            let shown = row(app, text)
            XCTAssertTrue(shown.waitForExistence(timeout: 20), "\(text) left @Mentions")
            let read = NSPredicate(format: "NOT (label CONTAINS 'ungelesen')")
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: read, evaluatedWith: shown)], timeout: 20), .completed,
                           "\(text) is still shown unread")
        }
        save(app, "mentions-read")
    }

    // MARK: - Helpers

    private func launch() -> XCUIApplication {
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
        return app
    }

    private func row(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Polls the server until the mention's read flag is `value`, for up to 20 seconds.
    private func waitForRead(_ me: TestServer, _ eventID: String, toBe value: Bool) throws -> Bool? {
        var last: Bool?
        for _ in 0..<20 {
            last = try me.mentionIsRead(eventID)
            if last == value { return last }
            sleep(1)
        }
        return last
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
