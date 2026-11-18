import XCTest

/// The header of a #one thread (Philip, 2026-11-18, option 2): the starter's picture,
/// "Thread von <Name>", "# <Raum>"; a tap opens the room at the thread's root.
final class ThreadHeaderUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var room: String { env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
    }

    func testHeaderNamesStarterAndRoomAndOpensTheRoom() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Kopfzeile Wurzel \(stamp)", in: room)
        _ = try other.send("Kopfzeile Antwort \(stamp)", in: room, thread: root)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        let header = app.descendants(matching: .any)["thread.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 120), "no thread header")
        let named = NSPredicate(format: "label CONTAINS 'Thread von Anna K.' AND label CONTAINS '# Allgemein'")
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: named, evaluatedWith: header)], timeout: 20) == .completed,
                      "header reads \"\(header.label)\"")
        sleep(2) // the starter's picture loads
        save(app, "thread-header")

        header.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Allgemein"].waitForExistence(timeout: 30), "the tap did not open the room")
        XCTAssertFalse(app.descendants(matching: .any)["thread.header"].exists, "still in the thread")
    }

    /// The text of a message starts at the sender name's x, in the first row and in every row
    /// that follows without a name: plain, a reply and a picture's caption, at a small and a
    /// large text size (Philip, 2026-11-18: the left edge wobbled at 190, 200, 203 px).
    func testMessageTextStartsAtTheSenderName() throws {
        for size in ["UICTContentSizeCategoryXS", "UICTContentSizeCategoryXXL"] {
            let other = try TestServer.signIn(2)
            // A picture, not initials: Element X scales pictures with the text size (the wobble).
            try other.setAvatar(colored: .systemOrange)
            let stamp = Int(Date().timeIntervalSince1970)
            let first = try other.send("Kante eins \(stamp)", in: room)
            _ = try other.sendContent(["msgtype": "m.text", "body": "Kante Antwort \(stamp)",
                                       "m.relates_to": ["m.in_reply_to": ["event_id": first]]], in: room)
            let mxc = try other.uploadPNG(colored: .systemTeal, width: 160, height: 90)
            _ = try other.sendContent(["msgtype": "m.image", "body": "Kante Bild \(stamp)", "filename": "bild.png", "url": mxc,
                                       "info": ["w": 160, "h": 90, "mimetype": "image/png"]], in: room)
            _ = try other.send("Kante zwei \(stamp)", in: room)
            try? other.setAvatar(colored: nil)
            other.signOut()

            let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room],
                             arguments: ["-UIPreferredContentSizeCategoryName", size])
            let last = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Kante zwei \(stamp)")).firstMatch
            XCTAssertTrue(last.waitForExistence(timeout: 120), "messages not shown")
            sleep(2)
            save(app, "left-edge-\(size.hasSuffix("XS") ? "small" : "large")")
            // Debug markers on each sender name and on each message text itself (inside any
            // inset). Our four rows are the newest texts; the name above them is the nearest.
            let texts = app.descendants(matching: .any).matching(identifier: "row.text").allElementsBoundByIndex
                .filter { $0.frame.height > 0 }.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertGreaterThanOrEqual(texts.count, 3, "\(size): too few text markers")
            let group = Array(texts.suffix(4))
            // The sender name sits in the same leading-aligned column as the text (TimelineRowStyler);
            // its marker reports no frame to XCUITest, so the rows are compared with each other.
            let x = group[0].frame.minX
            for text in group {
                XCTAssertEqual(text.frame.minX, x, accuracy: 0.5, "\(size): rows start at \(group.map(\.frame.minX))")
            }
            app.terminate()
        }
    }

    /// A back swipe started and cancelled leaves the header between the back button and the
    /// screen's edge (Philip, 2026-11-18: after a cancelled swipe the title ran under the buttons).
    func testHeaderStaysInPlaceAfterACancelledBackSwipe() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Zurückwisch Wurzel mit einem recht langen Text, der den Kopf füllt \(stamp)", in: room)
        _ = try other.send("Zurückwisch Antwort \(stamp)", in: room, thread: root)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        let header = app.descendants(matching: .any)["thread.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 120), "thread did not open")
        sleep(2)
        // From the screen's edge a third of the way, slowly, and let go: the pop cancels.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
        XCTAssertTrue(header.exists, "the swipe left the thread instead of cancelling")
        save(app, "cancelled-swipe")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertGreaterThanOrEqual(header.frame.minX, back.frame.maxX - 1,
                                    "the header runs under the back button: \(header.frame) vs \(back.frame)")
        XCTAssertLessThanOrEqual(header.frame.maxX, app.frame.width - 8, "the header runs off the screen: \(header.frame)")
    }

    /// Inside a thread a right swipe does nothing: no thread icon, nothing opens. In the room
    /// the right swipe still opens the message's thread (Philip, 2026-11-18).
    func testRightSwipeDoesNothingInsideAThread() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Wisch Wurzel \(stamp)", in: room)
        _ = try other.send("Wisch Antwort \(stamp)", in: room, thread: root)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["thread.header"].waitForExistence(timeout: 120), "thread did not open")
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        sleep(2)
        // As SwipeUITests swipes: 30 % to 90 % of the width, fast, along the newest row.
        let y = composer.frame.minY - 24
        let row = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.3, dy: y))
        row.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: y)),
                  withVelocity: .fast, thenHoldForDuration: 0.05)
        sleep(2)
        save(app, "thread-swipe")
        XCTAssertTrue(app.descendants(matching: .any)["thread.header"].exists, "the thread screen changed")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "thread.header").count, 1, "a second thread opened")

        // In the room, the right swipe still answers in the thread.
        app.navigationBars.buttons.firstMatch.tap()
        let roomComposer = app.textViews["Nachricht an # Allgemein"]
        XCTAssertTrue(roomComposer.waitForExistence(timeout: 30), "not back in the room")
        sleep(2)
        let mid = app.frame.height * 0.5
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.3, dy: mid))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: mid)),
                   withVelocity: .fast, thenHoldForDuration: 0.05)
        XCTAssertTrue(app.descendants(matching: .any)["thread.header"].waitForExistence(timeout: 15),
                      "the right swipe in the room no longer opens the thread")
    }

    /// A double tap on a message selects nothing and brings up no Writing Tools; "Text auswählen"
    /// in the long-press menu still selects (Philip, 2026-11-18; Alex wanted the menu item).
    func testDoubleTapSelectsNothingButTheMenuStillSelects() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let stamp = Int(Date().timeIntervalSince1970)
        _ = try other.send("Doppeltipp \(stamp) mit ein paar Wörtern", in: room)

        let app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room])
        let message = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Doppeltipp \(stamp)")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 120), "message not shown")
        sleep(1)
        // Message text reports no reliable frame to XCUITest; the newest message sits just above
        // the composer (as MessageMenuUITests aims).
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "no composer")
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.4, dy: composer.frame.minY - 24))
        target.doubleTap()
        sleep(1)
        save(app, "double-tap")
        // The simulator has no Apple Intelligence, so it never shows the Writing Tools button
        // Philip saw; this checks that nothing at all appears. The button itself is off by
        // MessageTextView.writingToolsBehavior = .none.
        for label in ["Copy", "Kopieren", "Writing Tools", "Schreibtools", "Look Up", "Nachschlagen"] {
            XCTAssertFalse(app.menuItems[label].exists || app.buttons[label].exists, "\(label) appeared after a double tap")
        }
        // A single tap opens a message's thread; the double tap's first tap may do so. Back to
        // the room for the long press.
        if app.descendants(matching: .any)["thread.header"].exists {
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            sleep(1)
        }

        // The menu's way still works: a long press on the row, as MessageMenuUITests does it.
        target.press(forDuration: 1.2)
        let select = app.buttons["Text auswählen"]
        XCTAssertTrue(select.waitForExistence(timeout: 10), "no \"Text auswählen\" in the menu")
        select.tap()
        XCTAssertTrue(app.textViews["text-selection.text"].waitForExistence(timeout: 10), "the selection sheet did not open")
        save(app, "select-text")
    }

    /// Every person's picture is a squircle (Philip, 2026-11-18): screenshots of @Mentions, the
    /// timeline with a picture and with initials, the thread summary, the profile sheet and Ich.
    func testAvatarsAreSquircles() throws {
        let other = try TestServer.signIn(2), me = try TestServer.signIn(1)
        addTeardownBlock { try? other.setAvatar(colored: nil); other.signOut(); me.signOut() }
        try other.setAvatar(colored: .systemPink)
        let stamp = Int(Date().timeIntervalSince1970)
        let root = try other.send("Formtest \(stamp)", in: room, mention: me.userID)
        _ = try other.send("Formtest Antwort \(stamp)", in: room, thread: root)

        var app = launch(["IPHONEBLOG_START_TAB": "mentions"])
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Formtest \(stamp)")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 120), "the mention is not listed")
        sleep(3)
        save(app, "avatars-mentions")
        app.terminate()

        app = launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "room did not open")
        sleep(3)
        save(app, "avatars-timeline")
        // The newest sender's name opens their profile.
        let names = app.descendants(matching: .any).matching(identifier: "row.senderName").allElementsBoundByIndex
        if let last = names.filter({ $0.frame.height > 0 }).max(by: { $0.frame.minY < $1.frame.minY }) {
            last.tap()
            sleep(2)
            save(app, "avatars-profile")
        }
        app.terminate()

        app = launch(["IPHONEBLOG_START_TAB": "me"])
        sleep(4)
        save(app, "avatars-me")
    }

    private func launch(_ extra: [String: String], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + arguments
        app.launch()
        return app
    }

    /// With TEST_RUNNER_IPHONEBLOG_SHOTS=1, a PNG in the runner's tmp folder iphoneblog-shots/,
    /// named after the simulator's appearance.
    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let style = env["IPHONEBLOG_SHOT_STYLE"] ?? "light"
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name)-\(style).png"))
    }
}
