import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

/// The test homeserver's client API, for UI tests that need another person to write: sign in as
/// a test user and send messages, as that person's own client would.
struct TestServer {
    let base: String
    let token: String
    let userID: String

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Signs in as IPHONEBLOG_TEST_USER (1), _USER2 (2) or _USER3 (3), or the server admin
    /// (IPHONEBLOG_TEST_ADMIN, number 0); skips without a server.
    static func signIn(_ number: Int) throws -> TestServer {
        let suffix = number == 1 ? "" : "\(number)"
        let userKey = number == 0 ? "IPHONEBLOG_TEST_ADMIN" : "IPHONEBLOG_TEST_USER\(suffix)"
        let passwordKey = number == 0 ? "IPHONEBLOG_TEST_ADMIN_PASSWORD" : "IPHONEBLOG_TEST_PASSWORD\(suffix)"
        guard let base = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env[userKey],
              let password = env[passwordKey] else {
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

    /// Whether this user has a highlight notification (a mention) whose body contains `text`.
    func hasMention(containing text: String) throws -> Bool {
        let page = try Self.call(base, "/_matrix/client/v3/notifications?only=highlight&limit=50", method: "GET", token: token, body: nil)
        return (page["notifications"] as? [[String: Any]] ?? []).contains { entry in
            let content = (entry["event"] as? [String: Any])?["content"] as? [String: Any]
            return (content?["body"] as? String ?? "").contains(text)
        }
    }

    /// Whether this user's highlight notification for the event counts as read on the server.
    func mentionIsRead(_ eventID: String) throws -> Bool? {
        let page = try Self.call(base, "/_matrix/client/v3/notifications?only=highlight&limit=50", method: "GET", token: token, body: nil)
        let entries = page["notifications"] as? [[String: Any]] ?? []
        let entry = entries.first { ($0["event"] as? [String: Any])?["event_id"] as? String == eventID }
        return entry?["read"] as? Bool
    }

    /// Uploads an endless animated GIF of eight coloured frames, 0.1 s each, and returns its mxc
    /// URL. Two screenshots 0.4 s apart always show different frames.
    func uploadGIF(width: Int = 240, height: Int = 160) throws -> String {
        let colors: [UIColor] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .magenta]
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, colors.count, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for color in colors {
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination), "GIF not written")
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/_matrix/media/v3/upload?filename=animation.gif")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/gif", forHTTPHeaderField: "Content-Type")
        request.httpBody = data as Data
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        let json = (try? JSONSerialization.jsonObject(with: result ?? Data())) as? [String: Any]
        return try XCTUnwrap(json?["content_uri"] as? String, "upload failed")
    }

    /// Uploads a plain coloured PNG and returns its mxc URI.
    func uploadPNG(colored color: UIColor, width: CGFloat = 96, height: CGFloat = 96) throws -> String {
        let png = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/_matrix/media/v3/upload?filename=picture.png")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.httpBody = png
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        let json = (try? JSONSerialization.jsonObject(with: result ?? Data())) as? [String: Any]
        return try XCTUnwrap(json?["content_uri"] as? String, "upload failed")
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

    /// The content of the newest message in the room whose body contains `text`, waiting up to
    /// 30 seconds for it to arrive.
    func message(in room: String, containing text: String) throws -> [String: Any]? {
        for _ in 0..<30 {
            let page = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(room))/messages?dir=b&limit=30",
                                     method: "GET", token: token, body: nil)
            for event in page["chunk"] as? [[String: Any]] ?? [] {
                if let content = event["content"] as? [String: Any], (content["body"] as? String)?.contains(text) == true {
                    return content
                }
            }
            sleep(1)
        }
        return nil
    }

    /// The newest event in the room whose content's `url` is this mxc (a GIF sent from the
    /// library), with its content; nil after 30 tries.
    func image(in room: String, mxc: String) throws -> [String: Any]? {
        for _ in 0..<30 {
            let page = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(room))/messages?dir=b&limit=30",
                                     method: "GET", token: token, body: nil)
            for event in page["chunk"] as? [[String: Any]] ?? [] {
                if let content = event["content"] as? [String: Any], content["url"] as? String == mxc { return content }
            }
            sleep(1)
        }
        return nil
    }

    /// One of this user's account data entries, or nil.
    func accountData(_ type: String) throws -> [String: Any]? {
        let result = try Self.call(base, "/_matrix/client/v3/user/\(Self.encode(userID))/account_data/\(type)", method: "GET",
                                   token: token, body: nil)
        return result["errcode"] == nil ? result : nil
    }

    /// Server admin only: the reasons of the newest event reports and user reports Synapse holds.
    func reportReasons() throws -> (events: [String], users: [String]) {
        let events = try Self.call(base, "/_synapse/admin/v1/event_reports?dir=b&limit=50", method: "GET", token: token, body: nil)
        let users = try Self.call(base, "/_synapse/admin/v1/user_reports?dir=b&limit=50", method: "GET", token: token, body: nil)
        func reasons(_ page: [String: Any]) -> [String] {
            (page["event_reports"] as? [[String: Any]] ?? page["user_reports"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
        }
        return (reasons(events), reasons(users))
    }

    /// A read receipt from this account, as another client would send it (thread "main" or a root).
    func readReceipt(_ eventID: String, in room: String, thread: String?) throws {
        _ = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(room))/receipt/m.read/\(Self.encode(eventID))",
                          method: "POST", token: token, body: thread.map { ["thread_id": $0] } ?? [:])
    }

    /// A room push rule for this account: "notify" for every event in the room, as the app's
    /// "Alle Nachrichten" for a room writes it; nil removes it.
    func setRoomRule(_ room: String, notify: Bool?) throws {
        let path = "/_matrix/client/v3/pushrules/global/room/\(Self.encode(room))"
        guard let notify else {
            _ = try? Self.call(base, path, method: "DELETE", token: token, body: nil)
            return
        }
        _ = try Self.call(base, path, method: "PUT", token: token, body: ["actions": notify ? ["notify"] : []])
    }

    /// The bytes behind an mxc:// URL, through the authenticated media API.
    func download(_ mxc: String) throws -> Data {
        let path = try XCTUnwrap(mxc.hasPrefix("mxc://") ? String(mxc.dropFirst(6)) : nil, "not an mxc URL: \(mxc)")
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/_matrix/client/v1/media/download/\(path)")))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return try XCTUnwrap(result, "no download")
    }

    /// This account's push rules of one kind ("override", "underride", "room"), by rule ID.
    func pushRules(_ kind: String) throws -> [String: [String: Any]] {
        let all = try Self.call(base, "/_matrix/client/v3/pushrules/", method: "GET", token: token, body: nil)
        let rules = ((all["global"] as? [String: Any])?[kind] as? [[String: Any]]) ?? []
        return Dictionary(rules.compactMap { rule in (rule["rule_id"] as? String).map { ($0, rule) } }) { first, _ in first }
    }

    /// Removes a push rule if it is there.
    func deleteRule(_ kind: String, _ ruleID: String) {
        let id = ruleID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))) ?? ruleID
        _ = try? Self.call(base, "/_matrix/client/v3/pushrules/global/\(kind)/\(id)", method: "DELETE", token: token, body: nil)
    }

    /// Edits a message (m.replace) and returns the edit's ID.
    func edit(_ event: String, in room: String, to body: String) throws -> String {
        try sendContent(["msgtype": "m.text", "body": "* \(body)",
                         "m.new_content": ["msgtype": "m.text", "body": body],
                         "m.relates_to": ["rel_type": "m.replace", "event_id": event]], in: room)
    }

    /// The event IDs in this account's notification list, highlights or not.
    func notifiedEvents() throws -> Set<String> {
        let page = try Self.call(base, "/_matrix/client/v3/notifications?limit=100", method: "GET", token: token, body: nil)
        return Set((page["notifications"] as? [[String: Any]] ?? []).compactMap { ($0["event"] as? [String: Any])?["event_id"] as? String })
    }

    /// This account's m.fully_read in a room (the Neu divider's place), if any.
    func fullyRead(in room: String) throws -> String? {
        let data = try Self.call(base, "/_matrix/client/v3/user/\(Self.encode(userID))/rooms/\(Self.encode(room))/account_data/m.fully_read",
                                 method: "GET", token: token, body: nil)
        return data["event_id"] as? String
    }

    /// Sets m.fully_read as another client would.
    func setFullyRead(_ eventID: String, in room: String) throws {
        _ = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(room))/read_markers", method: "POST", token: token,
                          body: ["m.fully_read": eventID])
    }

    /// Reacts to an event and returns the reaction's ID.
    func react(_ key: String, to event: String, in room: String) throws -> String {
        let path = "/_matrix/client/v3/rooms/\(Self.encode(room))/send/m.reaction/r\(UInt64(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 0..<1000))"
        let result = try Self.call(base, path, method: "PUT", token: token,
                                   body: ["m.relates_to": ["rel_type": "m.annotation", "event_id": event, "key": key]])
        return try XCTUnwrap(result["event_id"] as? String, "reaction failed")
    }

    /// Redacts an event and returns the redaction's ID.
    func redact(_ event: String, in room: String) throws -> String {
        let path = "/_matrix/client/v3/rooms/\(Self.encode(room))/redact/\(Self.encode(event))/x\(UInt64(Date().timeIntervalSince1970 * 1000))"
        let result = try Self.call(base, path, method: "PUT", token: token, body: [:])
        return try XCTUnwrap(result["event_id"] as? String, "redaction failed")
    }

    /// The server's notification count for this account in the room (the push badge's source).
    func notificationCount(in room: String) throws -> Int {
        let filter = #"{"room":{"rooms":["\#(room)"],"timeline":{"limit":1},"state":{"lazy_load_members":true}},"presence":{"not_types":["*"]},"account_data":{"not_types":["*"]}}"#
        // A distinct timeout per call: Synapse answers an identical /sync from its cache for two
        // minutes, so polling the same request would read the first count again and again.
        let sync = try Self.call(base, "/_matrix/client/v3/sync?timeout=\(Int.random(in: 1...999))&filter=\(filter.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")",
                                 method: "GET", token: token, body: nil)
        let joined = ((sync["rooms"] as? [String: Any])?["join"] as? [String: Any])?[room] as? [String: Any]
        return (joined?["unread_notifications"] as? [String: Any])?["notification_count"] as? Int ?? 0
    }

    /// Sends a message with any content (an article root, a formatted body). Returns its ID.
    @discardableResult
    func sendContent(_ content: [String: Any], in room: String) throws -> String {
        let path = "/_matrix/client/v3/rooms/\(Self.encode(room))/send/m.room.message/c\(UInt64(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 0..<1000))"
        let result = try Self.call(base, path, method: "PUT", token: token, body: content)
        return try XCTUnwrap(result["event_id"] as? String, "send failed")
    }

    /// A public room by name; returns its ID.
    func createRoom(_ name: String) throws -> String {
        let result = try Self.call(base, "/_matrix/client/v3/createRoom", method: "POST", token: token,
                                   body: ["name": name, "preset": "public_chat"])
        return try XCTUnwrap(result["room_id"] as? String, "createRoom failed")
    }

    /// A room where only its creator posts, as the server's read-only rooms (#releases): messages
    /// need power level 50, reactions stay open to everyone (docs/matrix.md in infra, read_only).
    func createReadOnlyRoom(_ name: String) throws -> String {
        let result = try Self.call(base, "/_matrix/client/v3/createRoom", method: "POST", token: token,
                                   body: ["name": name, "preset": "public_chat",
                                          "power_level_content_override": ["events": ["m.room.message": 50, "m.reaction": 0]]])
        return try XCTUnwrap(result["room_id"] as? String, "createRoom failed")
    }

    /// Makes a room a child of a space (as the #one space lists its rooms).
    func addChild(_ room: String, toSpace space: String, order: String) throws {
        _ = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(space))/state/m.space.child/\(Self.encode(room))",
                          method: "PUT", token: token, body: ["via": [String(userID.split(separator: ":").last ?? "localhost")], "order": order])
    }

    /// A room's ID by alias ("#one:localhost").
    func resolve(_ alias: String) throws -> String {
        let result = try Self.call(base, "/_matrix/client/v3/directory/room/\(Self.encode(alias))", method: "GET", token: token, body: nil)
        return try XCTUnwrap(result["room_id"] as? String, "no room \(alias)")
    }

    /// Joins a public room by ID.
    func join(_ room: String) throws {
        _ = try Self.call(base, "/_matrix/client/v3/join/\(Self.encode(room))", method: "POST", token: token, body: [:])
    }

    /// Whether this account's own receipts mark the event read, as the web chat and the app judge
    /// it (MentionsModel.withReadState): a receipt of the event's thread ("main" for the room's
    /// timeline) or an unthreaded one, at an event no older than it.
    func receiptsCover(_ eventID: String, in room: String, thread: String?) throws -> Bool {
        let filter = #"{"room":{"rooms":["\#(room)"],"timeline":{"limit":1},"state":{"lazy_load_members":true}},"presence":{"not_types":["*"]},"account_data":{"not_types":["*"]}}"#
        let sync = try Self.call(base, "/_matrix/client/v3/sync?filter=\(filter.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")",
                                 method: "GET", token: token, body: nil)
        let joined = ((sync["rooms"] as? [String: Any])?["join"] as? [String: Any])?[room] as? [String: Any]
        let events = (joined?["ephemeral"] as? [String: Any])?["events"] as? [[String: Any]] ?? []
        func time(_ id: String) throws -> Double {
            let event = try Self.call(base, "/_matrix/client/v3/rooms/\(Self.encode(room))/event/\(Self.encode(id))",
                                      method: "GET", token: token, body: nil)
            return event["origin_server_ts"] as? Double ?? 0
        }
        let target = try time(eventID)
        for event in events where event["type"] as? String == "m.receipt" {
            for (receipted, types) in event["content"] as? [String: [String: Any]] ?? [:] {
                for (type, users) in types where type == "m.read" || type == "m.read.private" {
                    guard let mine = (users as? [String: Any])?[userID] as? [String: Any] else { continue }
                    let receiptThread = mine["thread_id"] as? String
                    guard receiptThread == nil || receiptThread == (thread ?? "main") else { continue }
                    if try time(receipted) >= target { return true }
                }
            }
        }
        return false
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
