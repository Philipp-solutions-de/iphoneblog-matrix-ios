import XCTest

/// The search over blog and #one (ADR-0010), signed out, against the search API stand-in in
/// scripts/blog-fixture-server.py (60 mixed hits for any query, none for "nichts"). The fixture
/// counts every search request and every article page the Blog tab loads, so the test reads
/// what the app asked for, not WebKit's content (which CI's simulator hides from XCUITest).
final class SiteSearchUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8793" }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_SIGNED_OUT": "1",
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_BLOG_WEB": "\(fixture)/blog/?app=1",
            "IPHONEBLOG_BLOG_API": "\(fixture)/api",
            "IPHONEBLOG_SEARCH_URL": "\(fixture)/_iphoneblog/v1/search",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        let button = app.buttons["blog.search"]
        XCTAssertTrue(button.waitForExistence(timeout: 60), "no search in the Blog tab")
        button.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        // The field is focused when the search opens (with a hardware keyboard the simulator
        // shows no on-screen one, so the focus itself is checked).
        XCTAssertTrue(waitFor(5) { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true }, "the field is not focused")
        field.typeText(text)
    }

    private func hits(_ app: XCUIApplication, containing text: String = "") -> XCUIElementQuery {
        let format = text.isEmpty ? "identifier == 'site-search-hit'" : "identifier == 'site-search-hit' AND label CONTAINS %@"
        return app.descendants(matching: .any).matching(text.isEmpty ? NSPredicate(format: format) : NSPredicate(format: format, text))
    }

    /// Typing searches once after the pause, the list mixes kinds with their badges, a chip asks
    /// for its types, the end of the list loads the next page, and a video passage opens its
    /// article at the second when the reader is not in #one.
    func testMixedHitsFiltersPagesAndAVideoAtItsSecond() throws {
        let app = launch()
        let before = try searches().count
        search(app, "akku")
        XCTAssertTrue(hits(app, containing: "Beitrag").firstMatch.waitForExistence(timeout: 15), "no post hit")
        XCTAssertTrue(hits(app, containing: "Video").firstMatch.exists, "no video hit")
        XCTAssertTrue(hits(app, containing: "Diskussion").firstMatch.exists, "no discussion hit")
        XCTAssertTrue(hits(app, containing: "Nur für #one").firstMatch.exists, "a #one post is not marked for anonymous readers")
        XCTAssertFalse(hits(app, containing: "Chat").firstMatch.exists, "chat for an anonymous reader")
        attach(app, "site-search-all")

        let sent = try searches().dropFirst(before)
        XCTAssertEqual(sent.last?["q"] as? String, "akku")
        XCTAssertFalse(sent.contains { $0["auth"] as? Bool == true }, "signed out, but a token went out")
        XCTAssertTrue(sent.allSatisfy { ($0["q"] as? String ?? "").count >= 2 }, "a one-letter search went out")

        // The end of the list asks for page 2.
        // The keyboard covers the lower half: "Suchen" closes it, then the finger drags the list.
        // Without focus (a hardware keyboard, a list update) there is no return to type.
        let field = app.searchFields.firstMatch
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { field.typeText("\n") }
        XCTAssertTrue(waitFor(5) { !app.keyboards.firstMatch.exists }, "the keyboard stayed")
        for _ in 0..<10 { drag(app, from: 0.8, to: 0.3) }
        XCTAssertTrue(waitFor(10) { (try? self.searches().contains { $0["page"] as? Int == 2 }) ?? false }, "no second page")

        app.buttons["site-search.filter.videos"].tap()
        XCTAssertTrue(waitFor(10) { (try? self.searches().last?["types"] as? [String]) == ["video"] }, "the chip did not ask for videos")
        XCTAssertTrue(waitFor(10) { !self.hits(app, containing: "Beitrag").firstMatch.exists }, "a post under Videos")
        let video = hits(app, containing: "Video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        attach(app, "site-search-videos")

        // The filter's list starts at the top: the hit sits below the chips, where a finger
        // reaches it. XCUITest's own scroll-to-visible ignores the chips' inset and taps them.
        let chips = app.buttons["site-search.filter.videos"]
        XCTAssertTrue(waitFor(10) { video.isHittable && video.frame.minY >= chips.frame.maxY }, "the video hit is under the chips: \(video.frame), chips \(chips.frame)")
        let loads = try articleLoads().count
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitFor(15) { ((try? self.articleLoads()) ?? []).count > loads }, "the article did not open")
        let opened = try XCTUnwrap(articleLoads().last)
        XCTAssertTrue(opened.contains("/video-") && opened.contains("t=") && opened.contains("app=1"), opened)
        XCTAssertFalse(app.searchFields.firstMatch.exists, "the search stayed open")

        // Opened again, it shows what it showed.
        app.buttons["blog.search"].tap()
        XCTAssertTrue(hits(app, containing: "Video").firstMatch.waitForExistence(timeout: 5), "the search forgot its hits")
    }

    /// A post opens in the Blog tab's web view, a discussion reply in the article's discussion.
    func testAPostOpensInTheBlogAndAReplyInItsDiscussion() throws {
        let app = launch()
        search(app, "akku")
        let post = hits(app, containing: "Beitrag 1 ").firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 15), "no post hit")
        let loads = try articleLoads().count
        post.tap()
        XCTAssertTrue(waitFor(15) { ((try? self.articleLoads()) ?? []).count > loads }, "the post did not open")
        XCTAssertTrue(try XCTUnwrap(articleLoads().last).contains("/post-1/"))

        app.buttons["blog.search"].tap()
        app.buttons["site-search.filter.chat"].tap()
        XCTAssertTrue(waitFor(10) { (try? self.searches().last?["types"] as? [String]) == ["chat", "discussion"] }, "the chip did not ask for chat")
        XCTAssertTrue(waitFor(10) { !self.hits(app, containing: "Beitrag").firstMatch.exists }, "posts under Chat")
        let reply = hits(app, containing: "Diskussion").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10), "no discussion hit")
        reply.tap()
        XCTAssertTrue(app.navigationBars.buttons["Blog"].waitForExistence(timeout: 15), "the discussion did not open")
        attach(app, "site-search-discussion")
    }

    func testNoHitsSaysSo() throws {
        let app = launch()
        search(app, "nichts")
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 15))
    }

    // MARK: Helpers

    private func calls() throws -> [String: Any] {
        let url = try XCTUnwrap(URL(string: "\(fixture)/calls"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func searches() throws -> [[String: Any]] { try calls()["search"] as? [[String: Any]] ?? [] }
    private func articleLoads() throws -> [String] { try calls()["article_loads"] as? [String] ?? [] }

    private func waitFor(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    /// A finger drag over the middle of the screen, from one height to another (0 top, 1 bottom).
    private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 1500, thenHoldForDuration: 0)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
