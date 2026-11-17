import XCTest

/// The profile picture under Ich: set from the photo library, then removed; the server's profile
/// follows each step (testers: "Profilbilder lassen sich nicht setzen").
final class AvatarUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testSetAndRemoveTheProfilePicture() throws {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "me",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let choose = app.buttons["Bild wählen"]
        XCTAssertTrue(choose.waitForExistence(timeout: 120), "no Bild wählen under Ich")
        choose.tap()
        let picture = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo' OR label BEGINSWITH 'Foto'")).firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 45), "photo picker shows no pictures")
        sleep(1)
        picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["me.avatarRemove"].waitForExistence(timeout: 60), "the picture was not set")
        XCTAssertFalse(try avatarURL(server: server, user: user).isEmpty, "the server has no picture")
        attach(app, "avatar-set")

        app.buttons["me.avatarRemove"].tap()
        XCTAssertTrue(app.buttons["Bild wählen"].waitForExistence(timeout: 30), "the picture was not removed")
        XCTAssertTrue(try avatarURL(server: server, user: user).isEmpty, "the server still has a picture")
    }

    /// Another member's picture in @Mentions (Thorsten, 2026-11-17: only letters showed).
    func testMentionsShowTheSendersPicture() throws {
        let other = try TestServer.signIn(2)
        let me = try TestServer.signIn(1)
        defer { try? other.setAvatar(colored: nil); other.signOut(); me.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        try other.setAvatar(colored: .systemPink)
        let stamp = Int(Date().timeIntervalSince1970)
        try other.send("Bildtest \(stamp)", in: room, mention: me.userID)

        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "mentions", "IPHONEBLOG_EXPOSE_AVATARS": "1",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bildtest \(stamp)")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 120), "the mention is not in @Mentions")
        XCTAssertTrue(row.descendants(matching: .any)["avatar-image"].waitForExistence(timeout: 30)
                      || app.descendants(matching: .any)["avatar-image"].exists,
                      "@Mentions shows letters, not the sender's picture")
        attach(app, "mentions-avatar")
    }

    private func avatarURL(server: String, user: String) throws -> String {
        let url = try XCTUnwrap(URL(string: "\(server)/_matrix/client/v3/profile/%40\(user)%3Alocalhost/avatar_url"))
        var result: Data?
        let done = expectation(description: "profile")
        URLSession.shared.dataTask(with: url) { data, _, _ in result = data; done.fulfill() }.resume()
        wait(for: [done], timeout: 20)
        let json = (try? JSONSerialization.jsonObject(with: result ?? Data()) as? [String: Any]) ?? [:]
        return json["avatar_url"] as? String ?? ""
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
