import XCTest

/// The way from the blog into an article's discussion and back, driven like a reader does it.
/// scripts/build.sh ui starts scripts/blog-fixture-server.py and passes its address; the member
/// test also needs the test homeserver (scripts/test-homeserver.sh).
final class DiscussionUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8793" }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(member: Bool, extra: [String: String] = [:]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_BLOG_WEB": "\(fixture)/blog/?app=1",
            "IPHONEBLOG_BLOG_API": "\(fixture)/api",
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
        ].merging(extra) { _, new in new }
        if member {
            guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
                  let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
                throw XCTSkip("no test homeserver configured")
            }
            app.launchEnvironment.merge([
                "IPHONEBLOG_HOMESERVER": server,
                "IPHONEBLOG_DEV_USER": user,
                "IPHONEBLOG_DEV_PASSWORD": password,
                "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
                "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
                "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
            ]) { _, new in new }
        } else {
            app.launchEnvironment["IPHONEBLOG_SIGNED_OUT"] = "1"
        }
        // German, as the app's users read it: CI's simulator runs in English, and Element X's
        // labels ("Datei", "Bildunterschrift hinzufügen") follow the system language.
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    /// An article's video plays right in its card (Thorsten, 2026-11-20, blog-card-video.md):
    /// the poster with play, then the player. Captions are off until "CC" turns them on, and
    /// stay on for the next launch (Thorsten, 2026-11-21: "CC sollen default off sein und
    /// brauchen einen toggle"). A tap on the title, outside the player, still opens the
    /// article in the Blog tab.
    func testCardVideoPlaysInTheCard() throws {
        var app = try launch(member: false, extra: ["IPHONEBLOG_PLAYBACK_RESET": "1"])
        try playCardVideo(app)
        let caption = app.staticTexts["player.caption"]
        let toggle = app.buttons["player.captions"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no UT switch under the card's video")
        XCTAssertEqual(toggle.label, "Untertitel an", "captions are on by default")
        XCTAssertFalse(caption.waitForExistence(timeout: 4), "captions over the video although off")
        attach(app, "card-video-captions-off")
        toggle.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "UT did not turn the captions on")
        attach(app, "card-video-captions-on")

        // The choice is kept: the next launch plays with captions.
        app.terminate()
        app = try launch(member: false)
        try playCardVideo(app)
        XCTAssertEqual(app.buttons["player.captions"].label, "Untertitel aus", "the captions choice was not kept")
        XCTAssertTrue(app.staticTexts["player.caption"].waitForExistence(timeout: 20), "no captions after turning them on before")

        app.buttons["discussion.title"].tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 10), "the title does not open the article")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "not back in the Blog tab")
    }

    private func playCardVideo(_ app: XCUIApplication) throws {
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Artikel 1"].waitForExistence(timeout: 30), "blog page not loaded")
        let link = web.links["Diskussion 2"]
        for _ in 0..<6 where !link.isHittable { web.swipeUp(velocity: .slow) }
        link.tap()
        let play = app.buttons["card.video.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20), "the card shows no video")
        attach(app, "card-video-poster")
        play.tap()
        XCTAssertTrue(app.descendants(matching: .any)["card.video.player"].waitForExistence(timeout: 10), "no player in the card")
    }

    /// Signed out: the discussion of an article that has a thread opens read-only, without
    /// "Artikel lesen", and a swipe from the left edge returns to the blog where it was.
    func testReaderOpensDiscussionAndSwipesBack() throws {
        let app = try launch(member: false)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20), "no blog web view")
        XCTAssertTrue(web.staticTexts["Artikel 1"].waitForExistence(timeout: 20), "blog page not loaded")

        // Down to article 6, well below the first screen, so "the same place" means something.
        let link = web.links["Diskussion 6"]
        for _ in 0..<12 where !link.isHittable { web.swipeUp(velocity: .slow) }
        XCTAssertTrue(link.isHittable, "Diskussion 6 not reached")
        XCTAssertFalse(web.staticTexts["Artikel 1"].isHittable, "the blog did not scroll")
        let heading = web.staticTexts["Artikel 6"]
        let before = heading.frame.minY

        link.tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 45), "discussion did not open")
        XCTAssertTrue(app.staticTexts["Guter Punkt."].waitForExistence(timeout: 45), "replies not shown")
        XCTAssertFalse(app.buttons["Artikel lesen"].exists, "\"Artikel lesen\" is still there")
        attach(app, "reader-thread")

        swipeBackFromLeftEdge(app)
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 5), "swipe did not go back")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertFalse(web.staticTexts["Artikel 1"].isHittable, "the blog went back to the top")
        XCTAssertEqual(heading.frame.minY, before, accuracy: 2, "the blog lost its scroll position")
        attach(app, "reader-after-swipe-back")
    }

    /// Signed out, an article without a thread: no empty screen, an offer to sign in.
    func testReaderWithoutThreadIsOfferedSignIn() throws {
        let app = try launch(member: false)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 3"].waitForExistence(timeout: 20))
        web.links["Diskussion 3"].tap()
        XCTAssertTrue(app.staticTexts["Noch keine Antworten"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons["Anmelden"].exists)
        attach(app, "reader-no-thread")
    }

    /// Signed in: the first tap on an article without a thread has the server make one and
    /// opens it; the second tap opens the same thread without making another.
    func testMemberGetsAThreadMadeOnce() throws {
        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 1"].waitForExistence(timeout: 30))
        // The sign-in runs in the background; the thread needs the session.
        sleep(8)
        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 45))
        // The chat views expose senders, not message text: the bot's root by the test writer, and
        // the composer that answers in the thread.
        XCTAssertTrue(app.staticTexts["Stefan L."].firstMatch.waitForExistence(timeout: 30), "thread not opened")
        XCTAssertTrue(app.buttons["room-send_button"].exists, "no composer")
        attach(app, "member-thread")

        // At the top: the root, a line, the live count, and the first reply with its sender (the
        // root's writer answered, which must not read like a caption under the root).
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES '[0-9]+ Antworten|1 Antwort'")).firstMatch
        for _ in 0..<8 where !count.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(count.isHittable, "no reply count under the root")
        XCTAssertNotEqual(count.label, "0 Antworten")
        attach(app, "member-thread-top")

        swipeBackFromLeftEdge(app)
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 5), "swipe did not go back")
        attach(app, "member-after-swipe-back")

        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.staticTexts["Stefan L."].firstMatch.waitForExistence(timeout: 30), "second tap: thread not opened")
        let calls = try fixtureCalls()
        XCTAssertEqual(calls["created"], 1, "the server should make the thread once: \(calls)")
    }

    /// A member's reply in a discussion shows at once, and is still there after going back and
    /// opening the thread again (testers: "Wo ist meine Antwort?" until they restarted the app).
    func testMemberReplyShowsAndStays() throws {
        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 1"].waitForExistence(timeout: 30))
        sleep(8)
        web.links["Diskussion 1"].tap()
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 60), "no composer")
        sleep(3) // the thread loads
        composer.tap()
        let marker = "antwort\(Int.random(in: 1000...9999))"
        composer.typeText("Meine \(marker)")
        app.buttons["room-send_button"].tap()
        let reply = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "the reply does not show after sending")
        attach(app, "member-reply-sent")

        swipeBackFromLeftEdge(app)
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForNonExistence(timeout: 5), "swipe did not go back")
        sleep(12) // the guest file refetch and a sync pass
        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
            .waitForExistence(timeout: 30), "the reply is gone after reopening the thread")
        attach(app, "member-reply-reopened")
    }

    /// A thread with replies shows them on the first open, not only on the second (Brain's item
    /// d, 2026-11-21: "Blog-Thread zeigt beim ersten Öffnen nichts").
    func testMemberSeesTheRepliesOnTheFirstOpen() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_BLOG_ROOM"]), root = try XCTUnwrap(env["IPHONEBLOG_TEST_ARTICLE_ROOT"])
        try other.join(room) // the Blog room is public; the second person is not in it yet
        let marker = "erst\(Int.random(in: 1000...9999))"
        try other.send("Schon da \(marker)", in: room, thread: root)

        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 1"].waitForExistence(timeout: 30))
        sleep(8) // the sign-in runs in the background; the thread needs the session
        web.links["Diskussion 1"].tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 45))
        let reply = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "the thread's reply does not show on the first open")
        attach(app, "member-thread-first-open")
    }

    /// The reply count under the thread's first message follows a new reply while the thread is
    /// open (Brain's item d: "der Zähler vorne aktualisiert sich nicht").
    func testMemberSeesTheReplyCountGrow() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_BLOG_ROOM"]), root = try XCTUnwrap(env["IPHONEBLOG_TEST_ARTICLE_ROOT"])
        try other.join(room) // the Blog room is public; the second person is not in it yet
        try other.send("Vorher \(Int.random(in: 1000...9999))", in: room, thread: root)

        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 1"].waitForExistence(timeout: 30))
        sleep(8)
        web.links["Diskussion 1"].tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES '[0-9]+ Antworten|1 Antwort'")).firstMatch
        for _ in 0..<8 where !count.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(count.waitForExistence(timeout: 30), "no reply count under the root")
        let before = Int(count.label.prefix { $0.isNumber }) ?? 0
        XCTAssertGreaterThan(before, 0, "the count shows no replies: \(count.label)")

        try other.send("Neu \(Int.random(in: 1000...9999))", in: room, thread: root)
        let grown = NSPredicate { _, _ in (Int(count.label.prefix { $0.isNumber }) ?? 0) > before }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: grown, object: nil)], timeout: 30), .completed,
                       "the count stayed at \(count.label) after a new reply")
        attach(app, "member-thread-count-grown")
    }

    /// Philip's case (build 275, 2026-11-21, "Jump Desktop in Version 10"): an article a month
    /// old whose thread holds only replies from days ago, its root far behind the Blog room's
    /// newest events. Opened once, the thread shows its reply; a new reply raises the count.
    func testMemberOpensAnOldArticleThreadOnce() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_BLOG_ROOM"])
        try other.join(room)
        let stamp = Int.random(in: 1000...9999)
        let root = try other.send("Ein alter Artikel \(stamp)", in: room)
        _ = try other.send("Alte Antwort \(stamp)", in: room, thread: root)
        // Newer articles: the root ends up far behind the window a timeline loads first.
        for n in 1...40 { _ = try other.send("Neuerer Artikel \(n) \(stamp)", in: room) }

        // Article 4's discussion is this thread; opened the reader's way, from the blog.
        var request = URLRequest(url: try XCTUnwrap(URL(string: "\(fixture)/article-root")))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["article": 4, "root": root])
        let posted = XCTestExpectation(description: "fixture")
        URLSession.shared.dataTask(with: request) { _, _, _ in posted.fulfill() }.resume()
        wait(for: [posted], timeout: 10)

        let app = try launch(member: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Diskussion 4"].waitForExistence(timeout: 30))
        sleep(8) // the sign-in runs in the background; the thread needs the session
        web.links["Diskussion 4"].tap()
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 45), "the discussion did not open")
        let reply = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Alte Antwort \(stamp)")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "the old reply does not show on the first open")
        attach(app, "old-thread-first-open")

        // The root, far back, loads with the thread (ChatThreadCoordinator.loadRoot), and its
        // count follows a new reply.
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES '[0-9]+ Antworten|1 Antwort'")).firstMatch
        // The root sits above the reply; on a slow runner the count comes a little later
        // (main failed twice at a 10 s wait, 2026-11-27).
        for _ in 0..<8 where !count.isHittable { app.swipeDown(velocity: .fast) }
        if !count.waitForExistence(timeout: 20) {
            for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        }
        XCTAssertTrue(count.waitForExistence(timeout: 20), "no reply count under the root")
        XCTAssertEqual(count.label, "1 Antwort")
        try other.send("Neue Antwort \(stamp)", in: room, thread: root)
        let grown = NSPredicate { _, _ in count.label == "2 Antworten" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: grown, object: nil)], timeout: 30), .completed,
                       "the count stayed at \(count.label) after a new reply")
        attach(app, "old-thread-count-grown")
    }

    /// A chat link to a reply in an article's discussion, handed over at launch (iOS opens the
    /// app from a chat.iphoneblog.de link), opens that discussion with the reply in it, in the
    /// Blog tab (#bugs, build 320: "a launch link to a Blog reply opens nothing").
    func testLaunchLinkToABlogReplyOpensIt() throws {
        let other = try TestServer.signIn(2)
        defer { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_BLOG_ROOM"]), root = try XCTUnwrap(env["IPHONEBLOG_TEST_ARTICLE_ROOT"])
        try other.join(room) // the Blog room is public; the second person is not in it yet
        let marker = "verlinkt\(Int.random(in: 1000...9999))"
        let reply = try other.send("Antwort \(marker)", in: room, thread: root)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~$")
        let link = "https://chat.iphoneblog.de/#/" + [room, reply].map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "/")

        let app = try launch(member: true, extra: ["IPHONEBLOG_OPEN_URL": link])
        XCTAssertTrue(app.staticTexts["DISKUSSION"].waitForExistence(timeout: 90), "the link did not open the discussion")
        let shown = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 30), "the linked reply does not show")
        attach(app, "launch-link-blog-reply")
    }

    // MARK: Helpers

    private func swipeBackFromLeftEdge(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func fixtureCalls() throws -> [String: Int] {
        let data = try Data(contentsOf: XCTUnwrap(URL(string: "\(fixture)/calls")))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
}
