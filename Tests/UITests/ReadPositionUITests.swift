import XCTest

/// Tweetbot's read position (Thorsten, 2026-11-19): a room and a thread open where the reader
/// stopped, with "Zum Ende springen" to the newest; at the newest they open there, without it.
/// Kept on the device (ChatReadPositions). Rooms of their own in #one, so the shared channel's
/// seeded messages stay in reach for other tests.
final class ReadPositionUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testRoomOpensWhereTheReaderStopped() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        addTeardownBlock { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let room = try makeRoom("Lesetest \(stamp)", me: me, other: other)
        for n in 1...40 { try other.send("Lesen \(n) \(stamp)", in: room) }

        var app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        XCTAssertTrue(waitFor(30) { self.visible(app, "Lesen", 40, stamp) }, "the room does not open at the newest, \(shown(app, "Lesen", stamp))")
        XCTAssertFalse(app.buttons["room.jumpToEnd"].exists, "a jump button at the newest")
        for _ in 0..<4 { app.swipeDown(velocity: .slow) }
        sleep(2)
        let stopped = try XCTUnwrap(topmost(app, "Lesen", stamp), "no message on screen after scrolling up")
        XCTAssertLessThan(stopped, 28, "scrolling up did not move: \(shown(app, "Lesen", stamp))")
        XCTAssertTrue(app.buttons["room.jumpToEnd"].waitForExistence(timeout: 5), "no Zum Ende springen away from the newest")
        attach(app, "readpos-stopped")

        // Gone and back: a new launch reads the position from the device.
        app.terminate()
        app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120))
        XCTAssertTrue(waitFor(30) { abs((self.topmost(app, "Lesen", stamp) ?? 99) - stopped) <= 1 },
                      "opened at \(topmost(app, "Lesen", stamp) ?? -1), stopped at \(stopped)")
        let jump = app.buttons["room.jumpToEnd"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10), "no Zum Ende springen at a restored position")
        attach(app, "readpos-restored")
        jump.tap()
        XCTAssertTrue(waitFor(30) { self.visible(app, "Lesen", 40, stamp) }, "Zum Ende springen did not show the newest, \(shown(app, "Lesen", stamp))")
        XCTAssertTrue(jump.waitForNonExistence(timeout: 10), "the jump button stays at the newest")

        app.terminate()
        app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120))
        XCTAssertTrue(waitFor(30) { self.visible(app, "Lesen", 40, stamp) }, "left at the newest, it does not open there, \(shown(app, "Lesen", stamp))")
        sleep(2)
        XCTAssertFalse(app.buttons["room.jumpToEnd"].exists, "a jump button after leaving at the newest")
    }

    func testThreadOpensWhereTheReaderStopped() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        addTeardownBlock { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let room = try makeRoom("Fadentest \(stamp)", me: me, other: other)
        let root = try other.send("Fadenanfang \(stamp)", in: room)
        for n in 1...40 { try other.send("Faden \(n) \(stamp)", in: room, thread: root) }

        let app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'thread-row' AND label CONTAINS '40 Antworten'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no thread row")
        row.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "the thread did not open")
        XCTAssertTrue(waitFor(30) { self.visible(app, "Faden", 40, stamp) }, "the thread does not open at the newest, \(shown(app, "Faden", stamp))")
        for _ in 0..<3 { app.swipeDown(velocity: .slow) }
        sleep(2)
        let stopped = try XCTUnwrap(topmost(app, "Faden", stamp), "no reply on screen after scrolling up")
        XCTAssertLessThan(stopped, 28, "scrolling up did not move: \(shown(app, "Faden", stamp))")
        attach(app, "readpos-thread-stopped")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 30), "back did not return to the room")
        row.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(30) { abs((self.topmost(app, "Faden", stamp) ?? 99) - stopped) <= 1 },
                      "the thread opened at \(topmost(app, "Faden", stamp) ?? -1), stopped at \(stopped)")
        let jump = app.buttons["room.jumpToEnd"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10), "no Zum Ende springen in the thread")
        attach(app, "readpos-thread-restored")
        jump.tap()
        XCTAssertTrue(waitFor(30) { self.visible(app, "Faden", 40, stamp) }, "Zum Ende springen did not show the newest reply, \(shown(app, "Faden", stamp))")
    }

    /// The Neu divider follows m.fully_read, which moves with what the reader read when they
    /// leave the room (Thorsten, build 178: the jump always went to the same days-old message).
    func testFullyReadFollowsTheReader() throws {
        let me = try TestServer.signIn(1), other = try TestServer.signIn(2)
        addTeardownBlock { me.signOut(); other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let room = try makeRoom("Markertest \(stamp)", me: me, other: other)
        let hello = try me.send("Ab hier neu \(stamp)", in: room)
        try me.setFullyRead(hello, in: room)
        var last = ""
        for n in 1...30 { last = try other.send("Marke \(n) \(stamp)", in: room) }

        var app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        XCTAssertTrue(waitFor(30) { self.visible(app, "Marke", 30, stamp) }, "the room does not open at the newest, \(shown(app, "Marke", stamp))")
        sleep(3) // the receipt for the newest goes out
        // Leave: another tab; the room goes out of sight.
        let tab = app.tabBars.buttons["Für dich"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Für dich tab")
        tab.tap()
        XCTAssertTrue(waitFor(30) { (try? me.fullyRead(in: room)) == last },
                      "m.fully_read did not move to the newest read: \((try? me.fullyRead(in: room)) ?? "none") instead of \(last)")

        // New messages after that: the divider sits above the first of them, not above the old ones.
        for n in 31...33 { try other.send("Marke \(n) \(stamp)", in: room) }
        app.terminate()
        app = launch(room: room)
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120))
        let marker = app.descendants(matching: .any)["timeline.readMarker"]
        XCTAssertTrue(waitFor(30) { self.visible(app, "Marke", 33, stamp) && marker.exists }, "no Neu divider for the three new messages, \(shown(app, "Marke", stamp))")
        let first = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "Marke 31 \(stamp)")).firstMatch
        let before = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "Marke 30 \(stamp)")).firstMatch
        XCTAssertTrue(first.exists && before.exists, "the messages around the divider are not shown")
        XCTAssertTrue(before.frame.minY < marker.frame.minY && marker.frame.minY < first.frame.minY,
                      "the divider is not between Marke 30 and Marke 31")
        attach(app, "fully-read-moved")
    }

    // MARK: - Helpers

    private func makeRoom(_ name: String, me: TestServer, other: TestServer) throws -> String {
        let space = try me.resolve(env["IPHONEBLOG_ONE_ALIAS"] ?? "#one:localhost")
        let room = try me.createRoom(name)
        try me.addChild(room, toSpace: space, order: "z\(Int(Date().timeIntervalSince1970))")
        try me.send("Hallo", in: room)
        try other.join(room)
        return room
    }

    private func launch(room: String) -> XCUIApplication {
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
        return app
    }

    /// The messages "<word> N <stamp>" on screen between the header and the composer, top first,
    /// from one snapshot of the app (one query, not one per element: that took hours).
    private func onScreen(_ app: XCUIApplication, _ word: String, _ stamp: Int) -> [(number: Int, frame: CGRect)] {
        guard let root = try? app.snapshot() else { return [] }
        let window = app.windows.firstMatch.frame
        let pattern = try? NSRegularExpression(pattern: "\\b\(word) (\\d+) \(stamp)")
        var found: [Int: CGRect] = [:]
        func walk(_ node: XCUIElementSnapshot) {
            let label = node.label
            if node.elementType == .other, label.contains(" \(stamp)"),
               let match = pattern?.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
               let range = Range(match.range(at: 1), in: label), let number = Int(label[range]),
               node.frame.minY > window.minY + 120, node.frame.maxY < window.maxY - 120 {
                if found[number].map({ node.frame.height < $0.height }) ?? true { found[number] = node.frame }
            }
            node.children.forEach(walk)
        }
        walk(root)
        return found.map { (number: $0.key, frame: $0.value) }.sorted { $0.frame.minY < $1.frame.minY }
    }

    private func topmost(_ app: XCUIApplication, _ word: String, _ stamp: Int) -> Int? {
        onScreen(app, word, stamp).first?.number
    }

    private func visible(_ app: XCUIApplication, _ word: String, _ number: Int, _ stamp: Int) -> Bool {
        onScreen(app, word, stamp).contains { $0.number == number }
    }

    /// What is on screen, for a failure message.
    private func shown(_ app: XCUIApplication, _ word: String, _ stamp: Int) -> String {
        "on screen: \(onScreen(app, word, stamp).map(\.number))"
    }

    /// Polls until the condition holds or the deadline passes, by the clock, not by tries.
    private func waitFor(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return condition()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
