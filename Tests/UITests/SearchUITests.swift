import XCTest

/// Search in #one (Synapse's server-side search), against the test homeserver's seeded messages.
final class SearchUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tab: String) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": tab,
            "IPHONEBLOG_START_ROOM": tab == "chat" ? env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "" : "",
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

    private func openSearch() throws -> XCUIApplication {
        let app = try launch(tab: "chat")
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        app.buttons["room-search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        return app
    }

    private func hit(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'search-hit' AND label CONTAINS %@", text)).firstMatch
    }

    func testThreadReplyIsFoundAndOpensItsThread() throws {
        let app = try openSearch()
        app.searchFields.firstMatch.typeText("Comics")
        let result = hit(app, containing: "Comics in Panels")
        XCTAssertTrue(result.waitForExistence(timeout: 30), "thread reply not found")
        attach(app, "search-results")
        result.tap()
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 30), "the thread did not open")
        attach(app, "search-opened-thread")
    }

    func testChannelMessageJumpsIntoTheChannel() throws {
        let app = try openSearch()
        app.searchFields.firstMatch.typeText("vollen Kanal")
        let result = hit(app, containing: "Nachricht 3 im vollen Kanal")
        XCTAssertTrue(result.waitForExistence(timeout: 30), "channel message not found")
        result.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Allgemein"].waitForExistence(timeout: 30), "not back in the channel")
        sleep(2)
        attach(app, "search-jumped")
    }

    func testNoHitsSaysSo() throws {
        let app = try openSearch()
        app.searchFields.firstMatch.typeText("Quasselstrippe")
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 30))
        attach(app, "search-empty")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
