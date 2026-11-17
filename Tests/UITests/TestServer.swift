import UIKit
import XCTest

/// The test homeserver's client API, for UI tests that need another person to write: sign in as
/// a test user and send messages, as that person's own client would.
struct TestServer {
    let base: String
    let token: String
    let userID: String

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Signs in as IPHONEBLOG_TEST_USER (1), _USER2 (2) or _USER3 (3); skips without a server.
    static func signIn(_ number: Int) throws -> TestServer {
        let suffix = number == 1 ? "" : "\(number)"
        guard let base = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER\(suffix)"],
              let password = env["IPHONEBLOG_TEST_PASSWORD\(suffix)"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let login = try call(base, "/_matrix/client/v3/login", method: "POST", token: nil, body: [
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": user], "password": password,
        ])
        return TestServer(base: base, token: try XCTUnwrap(login["access_token"] as? String, "login failed"),
                          userID: try XCTUnwrap(login["user_id"] as? String))
    }

    /// Sends a text message; `mention` names a user in m.mentions, `thread` makes it a reply in
    /// that thread. Returns the event ID.
    @discardableResult
    func send(_ body: String, in room: String, mention: String? = nil, thread: String? = nil) throws -> String {
        var content: [String: Any] = ["msgtype": "m.text", "body": body]
        if let mention { content["m.mentions"] = ["user_ids": [mention]] }
        if let thread {
            content["m.relates_to"] = ["rel_type": "m.thread", "event_id": thread, "is_falling_back": true,
                                       "m.in_reply_to": ["event_id": thread]]
        }
        let path = "/_matrix/client/v3/rooms/\(Self.encode(room))/send/m.room.message/t\(UInt64(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 0..<1000))"
        let result = try Self.call(base, path, method: "PUT", token: token, body: content)
        return try XCTUnwrap(result["event_id"] as? String, "send failed")
    }

    /// Whether this user's highlight notification for the event counts as read on the server.
    func mentionIsRead(_ eventID: String) throws -> Bool? {
        let page = try Self.call(base, "/_matrix/client/v3/notifications?only=highlight&limit=50", method: "GET", token: token, body: nil)
        let entries = page["notifications"] as? [[String: Any]] ?? []
        let entry = entries.first { ($0["event"] as? [String: Any])?["event_id"] as? String == eventID }
        return entry?["read"] as? Bool
    }

    /// Uploads a small square picture and makes it this user's avatar; "" removes it.
    func setAvatar(colored color: UIColor?) throws {
        var url = ""
        if let color {
            let png = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            }
            var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/_matrix/media/v3/upload?filename=avatar.png")))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
            request.httpBody = png
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
            _ = semaphore.wait(timeout: .now() + 20)
            let json = (try? JSONSerialization.jsonObject(with: result ?? Data())) as? [String: Any]
            url = try XCTUnwrap(json?["content_uri"] as? String, "upload failed")
        }
        _ = try Self.call(base, "/_matrix/client/v3/profile/\(Self.encode(userID))/avatar_url", method: "PUT",
                          token: token, body: ["avatar_url": url])
    }

    /// One of this user's account data entries, or nil.
    func accountData(_ type: String) throws -> [String: Any]? {
        let result = try Self.call(base, "/_matrix/client/v3/user/\(Self.encode(userID))/account_data/\(type)", method: "GET",
                                   token: token, body: nil)
        return result["errcode"] == nil ? result : nil
    }

    func signOut() {
        _ = try? Self.call(base, "/_matrix/client/v3/logout", method: "POST", token: token, body: [:])
    }

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? segment
    }

    private static func call(_ base: String, _ path: String, method: String, token: String?, body: [String: Any]?) throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + path)))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return (try? JSONSerialization.jsonObject(with: result ?? Data()) as? [String: Any]) ?? [:]
    }
}
