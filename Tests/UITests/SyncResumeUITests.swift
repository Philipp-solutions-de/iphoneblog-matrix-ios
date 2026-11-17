import XCTest

/// After the app was in the background, new messages show without killing it (testers: "die App
/// aktualisiert sich nicht, ich muss sie abschiessen"). Sync stops in the background and starts
/// again in front (ChatSession.enterForeground).
final class SyncResumeUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testMessageWrittenWhileInBackgroundShowsInFront() throws {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"], let other = env["IPHONEBLOG_TEST_USER2"],
              let otherPassword = env["IPHONEBLOG_TEST_PASSWORD2"], let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_START_ROOM": room,
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
        sleep(3)

        XCUIDevice.shared.press(.home)
        sleep(20) // long enough for iOS to suspend the app and drop its connection
        let marker = "zurueck\(Int.random(in: 1000...9999))"
        try post("Während du weg warst: \(marker)", as: other, password: otherPassword, server: server, room: room)
        sleep(2)
        app.activate()

        let message = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 15), "the new message did not show after coming back")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sync-resumed"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func post(_ text: String, as user: String, password: String, server: String, room: String) throws {
        func call(_ path: String, method: String, token: String?, body: [String: Any]) throws -> [String: Any] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: server + path)))
            request.httpMethod = method
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            var result: Data?
            let done = expectation(description: path)
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; done.fulfill() }.resume()
            wait(for: [done], timeout: 20)
            return (try? JSONSerialization.jsonObject(with: result ?? Data()) as? [String: Any]) ?? [:]
        }
        let login = try call("/_matrix/client/v3/login", method: "POST", token: nil, body: [
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user], "password": password,
        ])
        let token = try XCTUnwrap(login["access_token"] as? String)
        let encoded = try XCTUnwrap(room.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        let sent = try call("/_matrix/client/v3/rooms/\(encoded)/send/m.room.message/\(UUID().uuidString)", method: "PUT",
                            token: token, body: ["msgtype": "m.text", "body": text])
        XCTAssertNotNil(sent["event_id"], "could not post: \(sent)")
    }
}
