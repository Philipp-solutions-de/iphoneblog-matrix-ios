import XCTest

/// "Alle" for a #one room is an underride for its messages (alle-notify-rule.md): a message
/// counts and pushes, a reaction or an edit does not. The old room rule counted every event.
final class AlleNotifyUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    /// "Alle" chosen on Ich writes the underride; then a message counts and lands in the
    /// notification list, a reaction and an edit do neither. The server pushes exactly what it
    /// counts there, so no count means no push.
    func testAlleCountsMessagesNotReactionsOrEdits() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 }, "no second #one room")
        let alle = "de.iphoneblog.alle.\(room)"
        addTeardownBlock {
            me.deleteRule("underride", alle); me.deleteRule("room", room); me.deleteRule("override", room)
            me.signOut(); other.signOut()
        }
        me.deleteRule("underride", alle); me.deleteRule("room", room); me.deleteRule("override", room)

        let app = launch()
        let menu = roomRow(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 120), "no Raum 2 row under Mitteilungen: \(rows(app))")
        XCTAssertTrue(waitFor(30) { menu.isEnabled && menu.label.contains("Nur Erwähnungen") }, "Raum 2 does not start at Nur Erwähnungen: \(menu.label)")
        menu.tap()
        let choice = app.buttons["Alle"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10), "no Alle in the menu")
        choice.tap()
        XCTAssertTrue(waitFor(30) { (try? me.pushRules("underride")[alle]) != nil }, "Alle wrote no underride")
        let written = try XCTUnwrap(try me.pushRules("underride")[alle])
        XCTAssertTrue(String(describing: written["conditions"]).contains("m.room.message"), "the underride is not for messages: \(written)")
        XCTAssertNil(try me.pushRules("room")[room], "Alle left a room rule")
        XCTAssertTrue(waitFor(10) { menu.label.contains("Alle") }, "the row does not read Alle: \(menu.label)")
        app.terminate() // a running app would read what comes next

        let message = try other.send("Alle-Test \(Int(Date().timeIntervalSince1970))", in: room)
        XCTAssertTrue(waitFor(30) { (try? me.notificationCount(in: room)) ?? 0 > 0 }, "a message in an Alle room counts nothing")
        XCTAssertTrue(try me.notifiedEvents().contains(message), "a message in an Alle room is not in the notification list")
        try me.readReceipt(message, in: room, thread: nil)
        XCTAssertTrue(waitFor(30) { (try? me.notificationCount(in: room)) == 0 }, "the receipt did not clear the count")

        let reaction = try other.react("👍", to: message, in: room)
        let edit = try other.edit(message, in: room, to: "Alle-Test bearbeitet")
        sleep(3)
        XCTAssertEqual(try me.notificationCount(in: room), 0, "a reaction or an edit counts in an Alle room")
        let notified = try me.notifiedEvents()
        XCTAssertFalse(notified.contains(reaction), "a reaction is in the notification list (it would push)")
        XCTAssertFalse(notified.contains(edit), "an edit is in the notification list (it would push)")

        let second = try other.send("Alle-Test zwei", in: room)
        XCTAssertTrue(waitFor(30) { (try? me.notificationCount(in: room)) == 1 }, "the next message does not count once")
        XCTAssertTrue(try me.notifiedEvents().contains(second))
    }

    /// The old form, a room rule with notify, becomes the underride when the app starts, and the
    /// row still reads Alle.
    func testOldRoomRuleMovesToTheUnderride() throws {
        let me = try TestServer.signIn(1)
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_ROOM2"].flatMap { $0.isEmpty ? nil : $0 }, "no second #one room")
        let alle = "de.iphoneblog.alle.\(room)"
        addTeardownBlock {
            me.deleteRule("underride", alle); me.deleteRule("room", room); me.deleteRule("override", room)
            me.signOut()
        }
        me.deleteRule("underride", alle); me.deleteRule("override", room)
        try me.setRoomRule(room, notify: true)

        let app = launch()
        XCTAssertTrue(waitFor(120) { (try? me.pushRules("underride")[alle]) != nil }, "the app did not write the underride")
        XCTAssertTrue(waitFor(30) { (try? me.pushRules("room")[room]) == nil }, "the old room rule is still there")
        let menu = roomRow(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "no Raum 2 row under Mitteilungen: \(rows(app))")
        XCTAssertTrue(waitFor(10) { menu.label.contains("Alle") }, "the row does not read Alle: \(menu.label)")
    }

    // MARK: - Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "me",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func roomRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "me.roomMode.Raum 2").firstMatch
    }

    private func rows(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'me.'")).allElementsBoundByIndex
            .map { "\($0.identifier)=\($0.label)" }.joined(separator: ", ")
    }

    private func waitFor(_ seconds: Int, _ condition: () -> Bool) -> Bool {
        for _ in 0..<seconds {
            if condition() { return true }
            sleep(1)
        }
        return condition()
    }
}
