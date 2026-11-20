import XCTest

/// A session the server no longer knows (revoked, or the server reset) ends in the app too: it
/// signs out on this device and says so, instead of staying "signed in" with nothing working.
final class SessionUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    func testRevokedSessionSignsOut() throws {
        // A second account (Anna): revoking the tester's tokens would disturb the tests after this one.
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER2"],
              let password = env["IPHONEBLOG_TEST_PASSWORD2"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": user,
            "IPHONEBLOG_DEV_PASSWORD": password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ]
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        // Anna has no #one: #one-Chat shows "Nur für #one-Mitglieder" with Abmelden.
        XCTAssertTrue(app.buttons["one.signOut"].waitForExistence(timeout: 120), "not signed in")

        // Every device of the account loses its token, as when the sign-in service revokes them.
        try revokeAllSessions(server: server, user: user, password: password)

        // Signing out returns to the Blog tab (with a short notice); #one-Chat then offers the sign-in.
        XCTAssertTrue(app.buttons["one.signOut"].waitForNonExistence(timeout: 90), "the app stayed signed in")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "session-lost"
        shot.lifetime = .keepAlways
        add(shot)
        app.tabBars.buttons["one"].tap()
        XCTAssertTrue(app.buttons["one.signIn"].waitForExistence(timeout: 10), "#one-Chat does not offer the sign-in")
        // The next test signs in again with the same password; nothing else to undo.
    }

    private func revokeAllSessions(server: String, user: String, password: String) throws {
        func call(_ path: String, token: String?, body: [String: Any]) throws -> [String: Any] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: server + path)))
            request.httpMethod = "POST"
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            var result: Data?
            let done = expectation(description: path)
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; done.fulfill() }.resume()
            wait(for: [done], timeout: 20)
            return (try? JSONSerialization.jsonObject(with: result ?? Data()) as? [String: Any]) ?? [:]
        }
        let login = try call("/_matrix/client/v3/login", token: nil, body: [
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user], "password": password,
        ])
        let token = try XCTUnwrap(login["access_token"] as? String)
        _ = try call("/_matrix/client/v3/logout/all", token: token, body: [:])
    }
}
