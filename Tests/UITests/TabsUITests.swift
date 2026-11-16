import XCTest

/// Who sees which tabs (Thorsten, 2026-11-16): #one members see Blog, #one-Chat, @Mentions and
/// Ich; everyone else Blog and #one-Chat, which offers the sign-in (signed out) or says
/// "Nur für #one-Mitglieder" with Abmelden and Konto löschen (signed in without #one).
final class TabsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func signIn(_ user: String?, _ password: String?) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user, let password else {
            throw XCTSkip("no test homeserver configured")
        }
        return launch(["IPHONEBLOG_HOMESERVER": server, "IPHONEBLOG_DEV_USER": user, "IPHONEBLOG_DEV_PASSWORD": password])
    }

    private func tabs(_ app: XCUIApplication) -> [String] {
        app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
    }

    func testSignedOutSeesBlogAndASignIn() {
        let app = launch(["IPHONEBLOG_SIGNED_OUT": "1"])
        XCTAssertTrue(app.buttons["one.signIn"].waitForExistence(timeout: 30), "no sign-in in #one-Chat")
        XCTAssertEqual(tabs(app), ["Blog", "#one-Chat"])
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'abonnieren' OR label CONTAINS[c] 'werden'")).firstMatch.exists,
                       "no way to buy")
        attach(app, "tabs-signed-out")
    }

    func testSignedInNonMemberSeesMembersOnly() throws {
        let app = try signIn(env["IPHONEBLOG_TEST_USER2"], env["IPHONEBLOG_TEST_PASSWORD2"]) // Anna: no #one
        XCTAssertTrue(app.buttons["one.signOut"].waitForExistence(timeout: 120), "not signed in")
        sleep(10) // membership is checked after sync; it must stay "no"
        XCTAssertTrue(app.staticTexts["Nur für #one-Mitglieder"].exists)
        XCTAssertTrue(app.buttons["one.deleteAccount"].exists, "no Konto löschen")
        XCTAssertEqual(tabs(app), ["Blog", "#one-Chat"])
        attach(app, "tabs-non-member")
    }

    func testMemberSeesAllFour() throws {
        let app = try signIn(env["IPHONEBLOG_TEST_USER"], env["IPHONEBLOG_TEST_PASSWORD"])
        XCTAssertTrue(app.tabBars.buttons["@Mentions"].waitForExistence(timeout: 120), "no member tabs")
        XCTAssertEqual(tabs(app), ["Blog", "#one-Chat", "@Mentions", "Ich"])
        attach(app, "tabs-member")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
