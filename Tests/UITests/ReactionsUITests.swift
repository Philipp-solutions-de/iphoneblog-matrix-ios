import XCTest

/// Reacting without the long press: the small button on a message's header opens the emoji
/// picker, and the chosen emoji arrives on the server as the tester's m.reaction.
final class ReactionsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testReactButtonAddsAReaction() throws {
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
        let react = app.buttons.matching(identifier: "row-react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: 30), "no react button on a message")
        let before = Date()
        react.tap()
        // Element X's emoji picker: "Reaktion hinzufügen: 😀".
        let emoji = app.buttons.matching(NSPredicate(format: "label CONTAINS '😀'")).firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 20), "no emoji picker")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "emoji-picker"
        shot.lifetime = .keepAlways
        add(shot)
        emoji.tap()
        XCTAssertTrue(try ownReactionArrived(server: server, user: user, password: password, after: before), "no reaction on the server")
    }

    private func ownReactionArrived(server: String, user: String, password: String, after: Date) throws -> Bool {
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
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user], "password": password,
        ])
        let token = try XCTUnwrap(login["access_token"] as? String)
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"]?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        for _ in 0..<30 {
            let page = try call("/_matrix/client/v3/rooms/\(room)/messages?dir=b&limit=30", method: "GET", token: token, body: nil)
            let found = (page["chunk"] as? [[String: Any]] ?? []).contains { event in
                event["type"] as? String == "m.reaction" && (event["sender"] as? String)?.hasPrefix("@\(user):") == true
                    && (event["origin_server_ts"] as? Double ?? 0) / 1000 >= after.timeIntervalSince1970 - 5
            }
            if found { return true }
            sleep(1)
        }
        return false
    }
}
