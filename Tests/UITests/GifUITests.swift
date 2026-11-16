import XCTest

/// Animated GIFs: a GIF in the channel plays (two screenshots a moment apart differ), and a GIF
/// from the photo library goes out unchanged (image/gif, not converted to JPEG). build.sh puts
/// scripts/fixtures/animation.gif into the simulator's library; the test server seeds one.
final class GifUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func openChannel() throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_START_ROOM": env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        return app
    }

    func testGifPlaysInTheChannel() throws {
        let app = try openChannel()
        sleep(6) // the GIF near the bottom loads
        let first = app.screenshot()
        usleep(400_000)
        let second = app.screenshot()
        attach(first, "gif-frame-a")
        attach(second, "gif-frame-b")
        XCTAssertNotEqual(first.pngRepresentation, second.pngRepresentation, "the GIF does not move")
    }

    func testGifFromLibraryIsSentUnchanged() throws {
        let app = try openChannel()
        let before = Date()
        app.buttons["composer_toolbar-open_compose_options"].tap()
        app.buttons["room-attachment_picker_photo_library"].tap()
        // build.sh added the GIF today; the picker labels each picture with its date, in the
        // system's language (it runs outside the app): "Foto, 16. November, 16:34" here,
        // "Photo, November 16, 4:34 PM" on CI's English simulator. No year for this year's.
        func today(_ locale: String, _ format: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.dateFormat = format
            return formatter.string(from: .now)
        }
        let added = app.images.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                                                    today("de_DE", "dd. MMMM,"), today("en_US", "MMMM d,")))
        XCTAssertTrue(added.firstMatch.waitForExistence(timeout: 45), "the GIF is not in the photo picker")
        // Earlier local runs added the GIF too; any of them will do, as long as it is on screen.
        let gif = added.allElementsBoundByIndex.first { $0.isHittable } ?? added.firstMatch
        sleep(1)
        gif.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Add"].tap()
        XCTAssertTrue(app.textViews["Bildunterschrift hinzufügen"].waitForExistence(timeout: 60), "no upload preview")
        app.buttons.matching(NSPredicate(format: "label == 'Senden' AND identifier != 'room-send_button'")).firstMatch.tap()
        let info = try latestOwnImageInfo(after: before)
        XCTAssertEqual(info["mimetype"] as? String, "image/gif", "the GIF was converted: \(info)")
    }

    // MARK: Helpers

    private func attach(_ shot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func latestOwnImageInfo(after: Date) throws -> [String: Any] {
        let server = try XCTUnwrap(env["IPHONEBLOG_TEST_HOMESERVER"])
        let user = try XCTUnwrap(env["IPHONEBLOG_TEST_USER"])
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        func call(_ path: String, method: String, token: String?, body: [String: Any]?) throws -> [String: Any] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: server + path)))
            request.httpMethod = method
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
            var result: Data?
            let done = expectation(description: path)
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; done.fulfill() }.resume()
            wait(for: [done], timeout: 20)
            return (try? JSONSerialization.jsonObject(with: result ?? Data()) as? [String: Any]) ?? [:]
        }
        let login = try call("/_matrix/client/v3/login", method: "POST", token: nil, body: [
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user],
            "password": try XCTUnwrap(env["IPHONEBLOG_TEST_PASSWORD"]),
        ])
        let token = try XCTUnwrap(login["access_token"] as? String)
        let encoded = try XCTUnwrap(room.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        for _ in 0..<40 {
            let page = try call("/_matrix/client/v3/rooms/\(encoded)/messages?dir=b&limit=20", method: "GET", token: token, body: nil)
            for event in page["chunk"] as? [[String: Any]] ?? [] {
                guard (event["sender"] as? String)?.hasPrefix("@\(user):") == true,
                      let content = event["content"] as? [String: Any], content["msgtype"] as? String == "m.image",
                      let ts = event["origin_server_ts"] as? Double, ts / 1000 >= after.timeIntervalSince1970 - 5 else { continue }
                return content["info"] as? [String: Any] ?? [:]
            }
            sleep(1)
        }
        XCTFail("no image from the tester on the server")
        return [:]
    }
}
