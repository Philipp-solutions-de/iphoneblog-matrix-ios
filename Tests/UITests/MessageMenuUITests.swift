import XCTest

/// A message's menu is German on an English iPhone, has no "Translate", and "Text auswählen"
/// shows the text in a sheet where part of it can be selected.
final class MessageMenuUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testMenuIsGermanAndSelectsText() throws {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"], let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": server, "IPHONEBLOG_DEV_USER": user, "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        // English on purpose: Alex's iPhone is English, and the menu must still be German.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        sleep(3)

        // Swipe left on a message in the middle of the timeline opens its menu.
        let y = app.frame.height * 0.5
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.2, dy: y)),
                   withVelocity: .fast, thenHoldForDuration: 0.05)

        let select = app.buttons["Text auswählen"]
        XCTAssertTrue(select.waitForExistence(timeout: 20), "no \"Text auswählen\" in the menu")
        for label in ["Im Thread antworten", "Link kopieren", "Text kopieren"] {
            XCTAssertTrue(app.buttons[label].exists, "menu lacks \"\(label)\"")
        }
        for label in ["Translate", "Übersetzen", "Reply", "Copy text", "Copy link"] {
            XCTAssertFalse(app.buttons[label].exists, "menu still shows \"\(label)\"")
        }
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "message-menu"
        menu.lifetime = .keepAlways
        add(menu)

        select.tap()
        let text = app.textViews["text-selection.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the selection sheet did not open")
        XCTAssertFalse((text.value as? String ?? "").isEmpty, "the selection sheet shows no text")
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "text-selection"
        sheet.lifetime = .keepAlways
        add(sheet)

        app.buttons["text-selection.done"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 10), "\"Fertig\" did not close the sheet")
    }
}
