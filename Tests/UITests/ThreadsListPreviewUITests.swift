import XCTest

/// Für dich › Threads reads like the rest of the app (Philip, 2026-11-17): a mention in a root's
/// body as "@Name", not "[Name](https://matrix.to/…)"; a sender by name, not by ID; an article
/// root by the article's title, not its URL.
final class ThreadsListPreviewUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testThreadsListShowsNamesTitlesAndPlainMentions() throws {
        let me = try TestServer.signIn(1)
        let other = try TestServer.signIn(2)
        defer { me.signOut(); other.signOut() }
        let channel = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let blog = try XCTUnwrap(env["IPHONEBLOG_TEST_BLOG_ROOM"].flatMap { $0.isEmpty ? nil : $0 }, "no blog room")
        let stamp = Int(Date().timeIntervalSince1970)

        // A root from another client with a markdown pill in body; the tester answers, so it is theirs.
        let pill = try other.sendContent([
            "msgtype": "m.text",
            "body": "[Tester](https://matrix.to/#/\(me.userID)) Pilltest \(stamp)",
            "format": "org.matrix.custom.html",
            "formatted_body": "<a href=\"https://matrix.to/#/\(me.userID)\">Tester</a> Pilltest \(stamp)",
        ], in: channel)
        try me.send("Antwort", in: channel, thread: pill)

        // An article root as the bot posts it: the URL as body, the title in de.iphoneblog.article.
        try other.join(blog)
        let article = try other.sendContent([
            "msgtype": "m.text",
            "body": "https://www.iphoneblog.de/2026/11/17/artikeltest-\(stamp)/",
            "de.iphoneblog.article": ["title": "Artikeltitel \(stamp)", "link": "https://www.iphoneblog.de/2026/11/17/artikeltest-\(stamp)/"],
        ], in: blog)
        try me.join(blog)
        try me.send("Mitgeredet", in: blog, thread: article)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Für dich"].waitForExistence(timeout: 120), "not signed in")
        app.tabBars.buttons["Für dich"].tap()
        let threads = app.segmentedControls.buttons["Threads"]
        XCTAssertTrue(threads.waitForExistence(timeout: 30), "no Threads filter in Für dich")
        threads.tap()

        let pillRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pilltest \(stamp)")).firstMatch
        XCTAssertTrue(pillRow.waitForExistence(timeout: 30), "the pill thread is not listed")
        XCTAssertFalse(pillRow.label.contains("matrix.to"), "the root shows the raw link: \(pillRow.label)")
        XCTAssertTrue(pillRow.label.contains("@Tester"), "the mention does not read @Tester: \(pillRow.label)")
        let name = NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "Anna K.", "@anna:")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: name, evaluatedWith: pillRow)], timeout: 15), .completed,
                       "the sender shows as an ID: \(pillRow.label)")

        let articleRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Artikeltitel \(stamp)")).firstMatch
        XCTAssertTrue(articleRow.waitForExistence(timeout: 30), "the article root does not show its title")
        XCTAssertFalse(articleRow.label.contains("https://"), "the article root still shows its URL: \(articleRow.label)")
        save(app, "threads-list-previews")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
