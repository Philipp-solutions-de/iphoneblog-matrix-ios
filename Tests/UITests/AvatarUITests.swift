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
