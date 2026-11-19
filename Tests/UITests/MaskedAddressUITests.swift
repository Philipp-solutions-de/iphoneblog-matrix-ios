import XCTest

/// The chat server masks addresses in messages (p***@***.de). A masked one is plain text, not a
/// mail or web link (Thorsten, 2026-11-19); a real web address in the same kind of message is.
final class MaskedAddressUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testMaskedAddressIsNoLink() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"].flatMap { $0.isEmpty ? nil : $0 })
        let stamp = Int(Date().timeIntervalSince1970)
        let masked = "Maske \(stamp): schreib an p***@***.de"
        let real = "Echt \(stamp): https://www.iphoneblog.de"
        try other.send(masked, in: room)
        // As a web or Element client sends a typed address once the server masked it: a mailto
        // link around the masked text, and the masked text in plain HTML.
        let maskedLink = "Maskenlink \(stamp)"
        try other.sendContent(["msgtype": "m.text", "body": "\(maskedLink) p***@***.de", "format": "org.matrix.custom.html",
                               "formatted_body": "\(maskedLink) <a href=\"mailto:p***@***.de\">p***@***.de</a>"], in: room)
        let maskedHTML = "Maskenhtml \(stamp)"
        try other.sendContent(["msgtype": "m.text", "body": "\(maskedHTML) p***@***.de", "format": "org.matrix.custom.html",
                               "formatted_body": "\(maskedHTML) <b>p***@***.de</b>"], in: room)
        try other.send(real, in: room)
        // Two after them, so neither sits on the composer.
        try other.send("Danach 1", in: room)
        try other.send("Danach 2", in: room)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": room,
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")

        let realRow = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "Echt \(stamp)")).firstMatch
        let maskedRow = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "Maske \(stamp)")).firstMatch
        XCTAssertTrue(realRow.waitForExistence(timeout: 30) && maskedRow.waitForExistence(timeout: 10), "the messages are not shown")
        XCTAssertGreaterThan(realRow.links.count, 0, "a real web address is no link; the check proves nothing")
        for row in [maskedRow,
                    app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", maskedLink)).firstMatch,
                    app.otherElements.matching(NSPredicate(format: "label CONTAINS %@", maskedHTML)).firstMatch] {
            XCTAssertTrue(row.waitForExistence(timeout: 10), "a masked message is not shown")
            XCTAssertEqual(row.links.count, 0, "a masked address is a link in \(row.label): \(row.links.allElementsBoundByIndex.map(\.label))")
        }
    }
}
