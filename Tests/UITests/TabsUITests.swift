import XCTest

/// Who sees which tabs (Thorsten, 2026-11-16/17): #one members see Blog, #one, Für dich and
/// Ich; everyone else Blog and #one, which offers the sign-in (signed out) or says
/// "Kein Zugang zu #one" with another account's sign-in and Konto löschen (signed in without
/// #one). Neither gate shows a price or a way to buy (spec-ios.md, App Store reader rule).
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
        XCTAssertEqual(tabs(app), ["Blog", "#one"])
        XCTAssertEqual(app.staticTexts["one.gate.text"].label, "Melde dich mit deinem iPhoneBlog-Konto an, um #one zu öffnen.")
        assertNoBuyWording(app)
        attach(app, "tabs-signed-out")
    }

    func testSignedInNonMemberSeesMembersOnly() throws {
        let app = try signIn(env["IPHONEBLOG_TEST_USER2"], env["IPHONEBLOG_TEST_PASSWORD2"]) // Anna: no #one
        XCTAssertTrue(app.buttons["one.signOut"].waitForExistence(timeout: 120), "not signed in")
        sleep(10) // membership is checked after sync; it must stay "no"
        XCTAssertTrue(app.staticTexts["Kein Zugang zu #one"].exists)
        XCTAssertTrue(app.staticTexts["one.gate.text"].label.hasSuffix("hat keinen Zugang zu #one."), app.staticTexts["one.gate.text"].label)
        XCTAssertEqual(app.buttons["one.signOut"].label, "Mit anderem Konto anmelden")
        XCTAssertTrue(app.buttons["one.deleteAccount"].exists, "no Konto löschen")
        assertNoBuyWording(app)
        XCTAssertEqual(tabs(app), ["Blog", "#one"])
        attach(app, "tabs-non-member")
    }

    func testMemberSeesAllFour() throws {
        let app = try signIn(env["IPHONEBLOG_TEST_USER"], env["IPHONEBLOG_TEST_PASSWORD"])
        XCTAssertTrue(app.tabBars.buttons["Für dich"].waitForExistence(timeout: 120), "no member tabs")
        XCTAssertEqual(tabs(app), ["Blog", "#one", "Für dich", "Ich"])
        attach(app, "tabs-member")
    }

    /// No price, no buy hint, no "Mitglied werden", no link to the offer.
    private func assertNoBuyWording(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let words = ["abonnieren", "werden", "kaufen", "Preis", "€", "Angebot", "Mitgliedschaft"]
        for element in app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex {
            for word in words where element.label.localizedCaseInsensitiveContains(word) {
                XCTFail("buy wording on the gate: \(element.label)", file: file, line: line)
            }
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
