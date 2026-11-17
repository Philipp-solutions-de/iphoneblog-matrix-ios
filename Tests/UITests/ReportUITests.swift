import XCTest

/// "Melden" on another member's message (App Review 1.2): a reason, "Senden", and the report is
/// on the server (read back through Synapse's admin API, which the moderators' mail follows).
final class ReportUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testReportAMessageReachesTheServer() throws {
        let other = try TestServer.signIn(2)
        let admin = try TestServer.signIn(0)
        defer { other.signOut(); admin.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let stamp = "Meldetest \(Int(Date().timeIntervalSince1970))"
        try other.send(stamp, in: room)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 120), "channel did not open")
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", stamp)).firstMatch.waitForExistence(timeout: 30),
                      "the message to report did not arrive")
        sleep(2)
        // The newest message sits just above the composer (message rows report no frame).
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width * 0.4, dy: composer.frame.minY - 24)).press(forDuration: 1.2)

        let report = app.buttons["Melden"]
        XCTAssertTrue(report.waitForExistence(timeout: 15), "no Melden in another member's message menu")
        report.tap()
        let send = app.buttons["report.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "the report sheet did not open")
        app.buttons["Beleidigung oder Belästigung"].tap()
        let note = app.textFields["report.note"].exists ? app.textFields["report.note"] : app.textViews["report.note"]
        note.tap()
        note.typeText(stamp)
        save(app, "report-message")
        send.tap()
        XCTAssertTrue(app.staticTexts["Danke. Die Moderation schaut es sich an."].waitForExistence(timeout: 20), "no thanks")

        var reasons: [String] = []
        for _ in 0..<10 where !reasons.contains(where: { $0.contains(stamp) }) {
            reasons = try admin.reportReasons().events
            if !reasons.contains(where: { $0.contains(stamp) }) { sleep(1) }
        }
        let reason = try XCTUnwrap(reasons.first { $0.contains(stamp) }, "the server has no such report")
        XCTAssertTrue(reason.hasPrefix("Beleidigung oder Belästigung"), "the reason is lost: \(reason)")
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        guard env["IPHONEBLOG_SHOTS"] == "1" else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iphoneblog-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
