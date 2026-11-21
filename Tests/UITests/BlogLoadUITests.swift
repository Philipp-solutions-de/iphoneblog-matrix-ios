import XCTest

/// The Blog tab loads its page once, and the #one hub asks for episodes only with the staff
/// gate's session (Philip's 500 in the Blog tab, build 220, 2026-11-20: several web views loaded
/// the blog at once and the episodes request followed the gate to /oauth2/start).
/// scripts/blog-fixture-server.py stands in for the blog and the gate and counts both.
final class BlogLoadUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8793" }

    override func setUp() {
        continueAfterFailure = false
    }

    /// Signed in: the start loads the blog once, and a tab switch there and back loads nothing.
    func testTabSwitchDoesNotReloadTheBlog() throws {
        let before = try count("blog_loads")
        let app = try launch(tab: "blog", blog: "/blog/?app=1")
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 120), "no blog web view")
        XCTAssertTrue(web.staticTexts["Artikel 1"].waitForExistence(timeout: 30), "blog page not loaded")
        // The session restores after the page: give the sign-in time to settle.
        XCTAssertTrue(oneTab(app).waitForExistence(timeout: 60))
        sleep(5)
        let started = try count("blog_loads")
        XCTAssertEqual(started - before, 1, "the start loaded the blog \(started - before) times")

        oneTab(app).tap()
        sleep(2)
        app.buttons["Blog"].firstMatch.tap()
        XCTAssertTrue(web.staticTexts["Artikel 1"].waitForExistence(timeout: 10), "the blog is gone after the tab switch")
        sleep(3)
        XCTAssertEqual(try count("blog_loads"), started, "the tab switch reloaded the blog")
    }

    /// Without a gate session the hub shows no episodes and starts no sign-in; after the Blog
    /// web view went through the gate, the hub shows them.
    func testHubAsksForEpisodesWithTheGateSession() throws {
        try post("/gate/reset")
        let gateBefore = try count("gate_starts"), gatedBefore = try count("episodes_gated")
        var app = try launch(tab: "chat", blog: "/blog/?app=1", hub: true)
        XCTAssertTrue(app.buttons["hub.tile.chat"].waitForExistence(timeout: 120), "no hub")
        XCTAssertTrue(waitFor(30) { (try? self.count("episodes_gated")) ?? 0 > gatedBefore }, "the hub did not ask for episodes")
        sleep(2)
        XCTAssertFalse(app.buttons["hub.hero"].exists, "episodes without a gate session")
        XCTAssertEqual(try count("gate_starts"), gateBefore, "the episodes request followed the gate's redirect")
        app.terminate()

        // The Blog web view signs in at the gate, as a tester does on beta.
        let okBefore = try count("episodes_ok")
        app = try launch(tab: "blog", blog: "/gate/start?rd=%2Fblog%2F%3Fapp%3D1", hub: true)
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Artikel 1"].waitForExistence(timeout: 120), "the gate did not lead to the blog")
        oneTab(app).tap()
        XCTAssertTrue(app.buttons["hub.hero"].waitForExistence(timeout: 60), "no episodes with the gate session")
        XCTAssertGreaterThan(try count("episodes_ok"), okBefore)
    }

    // MARK: Helpers

    /// The #one tab; its label is "one" since Thorsten's request of 2026-11-20 (#58).
    private func oneTab(_ app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons.matching(NSPredicate(format: "label IN {'#one', 'one'}")).firstMatch
    }

    private func launch(tab: String, blog path: String, hub: Bool = false) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_BLOG_WEB": fixture + path,
            "IPHONEBLOG_BLOG_API": "\(fixture)/api",
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": tab,
            "IPHONEBLOG_START_HUB": hub ? "1" : "",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func count(_ name: String) throws -> Int {
        let data = try request("/calls", method: "GET")
        let calls = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return calls[name] as? Int ?? 0
    }

    private func post(_ path: String) throws {
        _ = try request(path, method: "POST")
    }

    private func request(_ path: String, method: String) throws -> Data {
        var request = URLRequest(url: try XCTUnwrap(URL(string: fixture + path)))
        request.httpMethod = method
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return try XCTUnwrap(result, "the fixture server did not answer \(path)")
    }

    private func waitFor(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            if condition() { return true }
            sleep(1)
        }
        return condition()
    }
}
