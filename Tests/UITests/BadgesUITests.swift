import XCTest

/// The tab badges in a busy channel: scripts/test-homeserver.sh writes a mention of the tester
/// and ten messages after it into Allgemein. The SDK alone counts a room's mentions in its last
/// few events and loses this one; the app counts from the server's notification list. Runs
/// before the other UI tests (alphabetical), which read Allgemein and clear its unread state.
final class BadgesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testMentionBehindTenMessagesKeepsItsBadge() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "me", // not the channel: opening it would mark it read
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launch()

        // iOS 26's tab bar draws badges but does not expose them to accessibility, so the count
        // itself is checked in the sign-in test (Router.mentionsBadge, chatBadge); here the
        // screenshot keeps the badges, and @Mentions must list the mention as unread.
        let mentionsTab = app.tabBars.buttons["@Mentions"]
        XCTAssertTrue(mentionsTab.waitForExistence(timeout: 120), "not signed in")
        sleep(15) // membership, the room list and @Mentions load
        let badges = XCTAttachment(screenshot: app.screenshot())
        badges.name = "badges"
        badges.lifetime = .keepAlways
        add(badges)
        mentionsTab.tap()
        let unread = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'ungelesen'")).firstMatch
        XCTAssertTrue(unread.waitForExistence(timeout: 20), "the mention is not listed as unread")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "mentions"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// "Alle als gelesen" clears the unread mentions (runs after the test above: test order is
    /// alphabetical, and that one needs the mention unread).
    func testMentionsMarkAllReadClearsThem() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "mentions",
            "IPHONEBLOG_HOMESERVER": server, "IPHONEBLOG_DEV_USER": user, "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let button = app.buttons["mentions.markAllRead"]
        XCTAssertTrue(button.waitForExistence(timeout: 120), "no Alle als gelesen with an unread mention")
        button.tap()
        let unread = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'ungelesen'")).firstMatch
        XCTAssertTrue(unread.waitForNonExistence(timeout: 30), "the mention is still unread")
        XCTAssertTrue(button.waitForNonExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "mentions-all-read"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
