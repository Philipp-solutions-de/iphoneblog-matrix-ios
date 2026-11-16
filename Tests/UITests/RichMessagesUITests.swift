import XCTest

/// Rich messages in #one-Chat and in an article's Diskussion: what the timeline shows and what
/// the composer sends. scripts/test-homeserver.sh seeds one message of each kind
/// (scripts/test-rich-messages.py) at the end of Allgemein and in the article's thread; the
/// screenshots are the record of how they look. What the composer sends is read back from the
/// server, so a green test means the event left the phone formatted.
final class RichMessagesUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private struct Server {
        let url: String
        let user: String
        let password: String
    }

    private func server() throws -> Server {
        guard let url = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        return Server(url: url, user: user, password: password)
    }

    private func launch(_ extra: [String: String]) throws -> XCUIApplication {
        let server = try server()
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            "IPHONEBLOG_HOMESERVER": server.url,
            "IPHONEBLOG_DEV_USER": server.user,
            "IPHONEBLOG_DEV_PASSWORD": server.password,
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
            "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        // German, as the app's users read it: CI's simulator runs in English, and Element X's
        // labels ("Datei", "Bildunterschrift hinzufügen") follow the system language.
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func openChannel() throws -> XCUIApplication {
        let app = try launch(["IPHONEBLOG_START_TAB": "chat"])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        return app
    }

    /// The seeded set in Allgemein: formatted text, a link with its preview, a reply's quote,
    /// then a picture, a video and a PDF.
    func testChannelShowsRichMessages() throws {
        let app = try openChannel()
        XCTAssertTrue(fileRow(app).waitForExistence(timeout: 90), "file not shown")
        sleep(4) // pictures and the link preview load
        attach(app, "channel-media")
        scrollTimeline(app, toFind: "Lies das")
        app.swipeDown(velocity: .slow)
        sleep(2)
        attach(app, "channel-text")
    }

    /// The same set as replies in an article's Diskussion.
    func testDiscussionShowsRichMessages() throws {
        guard let root = env["IPHONEBLOG_TEST_ARTICLE_ROOT"], !root.isEmpty else { throw XCTSkip("no article thread") }
        let app = try launch(["IPHONEBLOG_START_DISCUSSION": root])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "discussion did not open")
        XCTAssertTrue(fileRow(app).waitForExistence(timeout: 90), "file not shown")
        sleep(4)
        attach(app, "discussion-media")
        scrollTimeline(app, toFind: "Lies das")
        app.swipeDown(velocity: .slow)
        sleep(2)
        attach(app, "discussion-text")
    }

    /// Markdown typed into the composer leaves as formatted HTML; a bare address stays a link.
    func testComposerSendsMarkdown() throws {
        let app = try openChannel()
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "no composer")
        composer.tap()
        let marker = "md\(Int.random(in: 1000...9999))"
        composer.typeText("**fett** und *schräg* \(marker) https://www.iphoneblog.de/")
        app.buttons["room-send_button"].tap()
        let event = try latestOwnMessage(containing: marker)
        let html = event["formatted_body"] as? String ?? ""
        XCTAssertTrue(html.contains("<strong>fett</strong>"), "not bold: \(html)")
        XCTAssertTrue(html.contains("<em>schräg</em>"), "not italic: \(html)")
        sleep(3)
        attach(app, "composer-markdown-sent")
    }

    /// + › Textformatierung opens Element X's toolbar; bold from it arrives as <strong>.
    func testFormattingToolbarSendsBold() throws {
        let app = try openChannel()
        app.buttons["composer_toolbar-open_compose_options"].tap()
        let formatting = app.buttons["room-attachment_picker_text_formatting"]
        XCTAssertTrue(formatting.waitForExistence(timeout: 5), "no Textformatierung in the + menu")
        formatting.tap()
        let bold = app.switches["composer_toolbar-bold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5), "no formatting toolbar")
        bold.tap()
        let marker = "rt\(Int.random(in: 1000...9999))"
        app.typeText("dick\(marker)")
        attach(app, "composer-formatting-toolbar")
        app.buttons["room-send_button"].tap()
        let event = try latestOwnMessage(containing: marker)
        let html = event["formatted_body"] as? String ?? ""
        XCTAssertTrue(html.contains("<strong>dick\(marker)</strong>"), "not bold: \(html)")
    }

    /// + › Fotos: a picture from the library goes up through the upload preview and arrives as
    /// m.image. The screenshot right after Senden catches the progress bar when the upload is slow
    /// enough to see.
    func testPhotoFromLibraryIsSent() throws {
        let app = try openChannel()
        let event = try sendPhoto(app)
        XCTAssertNil(event["m.relates_to"], "a channel photo should not be in a thread: \(event)")
    }

    /// The same in a thread: the picture arrives as a thread reply.
    func testPhotoInThreadIsSent() throws {
        guard let room = env["IPHONEBLOG_TEST_CHANNEL_ROOM"], let root = env["IPHONEBLOG_TEST_CHANNEL_THREAD"] else {
            throw XCTSkip("no channel thread")
        }
        let app = try launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        XCTAssertTrue(app.textViews["Antworten…"].waitForExistence(timeout: 120), "thread did not open")
        let event = try sendPhoto(app, shotPrefix: "thread-")
        let relation = event["m.relates_to"] as? [String: Any]
        XCTAssertEqual(relation?["rel_type"] as? String, "m.thread", "the photo did not go into the thread: \(event)")
        XCTAssertEqual(relation?["event_id"] as? String, root)
    }

    /// + › Fotos, the first library picture, Senden in the upload preview; returns the server's event.
    private func sendPhoto(_ app: XCUIApplication, shotPrefix: String = "") throws -> [String: Any] {
        let before = Date()
        app.buttons["composer_toolbar-open_compose_options"].tap()
        let photos = app.buttons["room-attachment_picker_photo_library"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5), "no Fotos in the + menu")
        photos.tap()

        // The system photo picker runs in its own process but shows inside the app.
        let picture = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo' OR label BEGINSWITH 'Foto'")).firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 45), "photo picker shows no pictures")
        sleep(1) // the sheet slides in; the picture is not hittable until it rests
        picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let add = app.buttons["Add"] // the picker's checkmark, "Fertig"
        XCTAssertTrue(add.waitForExistence(timeout: 5), "picker has no Fertig")
        add.tap()

        // The upload preview: a caption field and its own Senden. The composer's send button
        // (room-send_button) waits behind the sheet with the same label.
        let caption = app.textViews["Bildunterschrift hinzufügen"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60), "no upload preview")
        attach(app, shotPrefix + "upload-preview")
        let send = app.buttons.matching(NSPredicate(format: "label == 'Senden' AND identifier != 'room-send_button'")).firstMatch
        XCTAssertTrue(send.isHittable, "upload preview's Senden not hittable")
        send.tap()
        sleep(2)
        attach(app, shotPrefix + "upload-sending")
        let event = try latestOwnMessage(msgtype: "m.image", after: before)
        XCTAssertNotNil(event["url"], "image without a file: \(event)")
        sleep(3)
        attach(app, shotPrefix + "upload-sent")
        return event
    }

    // MARK: Helpers

    /// The PDF's row; Element X labels a file "Datei" for VoiceOver.
    private func fileRow(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Datei' OR label CONTAINS 'dokument.pdf'")).firstMatch
    }

    /// Swipes the timeline down (towards older messages) until a text shows, at most eight times.
    private func scrollTimeline(_ app: XCUIApplication, toFind text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        for _ in 0..<8 where !app.staticTexts.matching(predicate).firstMatch.isHittable {
            app.swipeDown(velocity: .slow)
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Reading back from the server

    private func call(_ path: String, method: String = "GET", token: String? = nil, body: [String: Any]? = nil) throws -> [String: Any] {
        let server = try server()
        var request = URLRequest(url: try XCTUnwrap(URL(string: server.url + path)))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        var result: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: request) { data, _, error in
            result = data.map { .success($0) } ?? .failure(error ?? URLError(.badServerResponse))
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: result.get()) as? [String: Any])
    }

    /// The newest message the tester sent to Allgemein that matches; waits up to 30 s for it.
    private func latestOwnMessage(containing text: String? = nil, msgtype: String? = nil, after: Date? = nil) throws -> [String: Any] {
        let server = try server()
        let login = try call("/_matrix/client/v3/login", method: "POST", body: [
            "type": "m.login.password", "identifier": ["type": "m.id.user", "user": server.user], "password": server.password,
        ])
        let token = try XCTUnwrap(login["access_token"] as? String)
        defer { _ = try? call("/_matrix/client/v3/logout", method: "POST", token: token, body: [:]) }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"], "no channel room")
        let encoded = try XCTUnwrap(room.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        for _ in 0..<30 {
            let page = try call("/_matrix/client/v3/rooms/\(encoded)/messages?dir=b&limit=20", token: token)
            for event in page["chunk"] as? [[String: Any]] ?? [] {
                guard event["type"] as? String == "m.room.message",
                      (event["sender"] as? String)?.hasPrefix("@\(server.user):") == true,
                      let content = event["content"] as? [String: Any] else { continue }
                if let text, !(content["body"] as? String ?? "").contains(text) { continue }
                if let msgtype, content["msgtype"] as? String != msgtype { continue }
                if let after, let ts = event["origin_server_ts"] as? Double, ts / 1000 < after.timeIntervalSince1970 - 5 { continue }
                return content
            }
            sleep(1)
        }
        XCTFail("message not on the server")
        return [:]
    }
}
