import ImageIO
import UniformTypeIdentifiers
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
        let app = try launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? ""])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        return app
    }

    /// The seeded set in Allgemein: formatted text, a link with its preview, a reply's quote,
    /// then a picture, a video and a PDF.
    func testChannelShowsRichMessages() throws {
        let app = try openChannel()
        // Tests that run earlier write into Allgemein too (the hub's, for one), so the seeded set
        // may sit above the screen: wait for the timeline, then scroll up to the PDF.
        // Each suite added there pushes it further up (25 swipes; 10 stopped short on CI once
        // the hub's and the long-press tests had written), and a swipe can carry past the row
        // while the list still moves, so the search also comes back down.
        if !fileRow(app).waitForExistence(timeout: 30) {
            for _ in 0..<25 where !onScreen(fileRow(app), app) {
                app.swipeDown(velocity: .slow)
                _ = fileRow(app).waitForExistence(timeout: 2)
            }
            for _ in 0..<25 where !onScreen(fileRow(app), app) {
                app.swipeUp(velocity: .slow)
                _ = fileRow(app).waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(fileRow(app).waitForExistence(timeout: 30), "file not shown")
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

    /// One's own picture shows once it is on the server, even when the local copy the timeline
    /// showed while sending cannot be read (Philip's picture in #bugs, 2026-11-18, stayed a
    /// blurhash: the timeline kept loading the local copy and never asked the server). The app is
    /// told to fail every local copy; the picture must still appear.
    func testOwnPhotoShowsWhenTheLocalCopyFails() throws {
        let app = try launch(["IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_ROOM": env["IPHONEBLOG_TEST_CHANNEL_ROOM"] ?? "",
                              "IPHONEBLOG_FAIL_LOCAL_MEDIA": "1"])
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "channel did not open")
        _ = try sendPhoto(app, shotPrefix: "local-fail-")
        let waiting = app.descendants(matching: .any).matching(identifier: "timeline-image.waiting")
        let until = Date().addingTimeInterval(60)
        while Date() < until, waiting.count > 0 { sleep(1) }
        attach(app, "local-fail-after")
        XCTAssertEqual(waiting.count, 0, "a picture in the timeline still shows only its blurhash")
        XCTAssertTrue(app.descendants(matching: .any)["timeline-image.loaded"].exists, "no loaded picture in sight")
    }

    /// A picture's caption keeps its first letter: the rounded corners belong to the picture,
    /// not to the caption below it (Philip, 2026-11-20, "Ein Kreis" lost the left of its E).
    func testCaptionIsNotClippedByThePicturesCorner() throws {
        let anna = try TestServer.signIn(2)
        defer { anna.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let text = "Ein Kreis \(Int(Date().timeIntervalSince1970) % 100_000)"
        try anna.sendContent(["msgtype": "m.image", "body": text, "filename": "picture.png",
                              "url": try anna.uploadPNG(colored: .systemGray4, width: 240, height: 160),
                              "info": ["mimetype": "image/png", "w": 240, "h": 160]], in: room)
        let app = try openChannel()
        // The caption's own text view: on screen (a frame), narrower than the row.
        let candidates = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text))
        let until = Date().addingTimeInterval(60)
        var found: XCUIElement?
        while found == nil, Date() < until {
            found = candidates.allElementsBoundByIndex.first { element in
                let frame = element.frame
                return frame.width > 20 && frame.height > 8 && frame.width < app.frame.width * 0.9 && app.frame.contains(frame)
            }
            if found == nil { sleep(1) }
        }
        let element = try XCTUnwrap(found, "the caption is not in the channel")
        attach(app, "caption-timeline")
        // The E's stem is the caption's leftmost ink. Cut by the picture's rounded corner, it
        // lost its lower part; whole, it is as tall as the rest of the text.
        let shot = try XCTUnwrap(element.screenshot().image.cgImage)
        let width = shot.width, height = shot.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(shot, in: CGRect(x: 0, y: 0, width: width, height: height))
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3 < 110
        }
        func rows(columns: Range<Int>) -> (top: Int, bottom: Int) {
            var top = height, bottom = -1
            for x in columns { for y in 0..<height where isInk(x, y) { top = min(top, y); bottom = max(bottom, y) } }
            return (top, bottom)
        }
        let first = try XCTUnwrap((0..<width).first { x in (0..<height).contains { isInk(x, $0) } }, "no text in the caption")
        // The first letters only, so no other text in the element counts.
        let whole = rows(columns: first..<min(first + 60, width))
        let stem = rows(columns: first..<min(first + 3, width))
        let measured = XCTAttachment(string: "first ink column \(first), stem rows \(stem), text rows \(whole), width \(width)")
        measured.name = "caption-measure"
        measured.lifetime = .keepAlways
        add(measured)
        // Where the rounded corner cut, the stem stopped short of the line's foot (measured
        // 2026-11-20: 6 px short before the fix, 1 px after).
        XCTAssertGreaterThanOrEqual(stem.bottom, whole.bottom - 2,
                                    "the caption's first letter is cut at the lower left (stem rows \(stem), text rows \(whole))")
    }

    /// "@Anna" in a picture's caption (Philip, 2026-11-18: a caption's mention reached nobody):
    /// picked from the @ suggestions, sent as a mention (m.mentions, a link in formatted_body,
    /// the name as plain text in body), and Anna gets a mention.
    func testCaptionMentionReachesThePerson() throws {
        let anna = try TestServer.signIn(2)
        addTeardownBlock { anna.signOut() }
        let app = try openChannel()
        let stamp = Int(Date().timeIntervalSince1970)
        let event = try sendPhoto(app, shotPrefix: "caption-mention-", caption: "Bild \(stamp) für @Ann", mention: "Anna K.")
        let mentions = (event["m.mentions"] as? [String: Any])?["user_ids"] as? [String] ?? []
        XCTAssertEqual(mentions, [anna.userID], "m.mentions: \(event)")
        let html = event["formatted_body"] as? String ?? ""
        XCTAssertTrue(html.contains("https://matrix.to/#/\(anna.userID)"), "no mention link in formatted_body: \(event)")
        let body = event["body"] as? String ?? ""
        XCTAssertTrue(body.contains("Bild \(stamp) für") && body.contains("Anna K.") && !body.contains("]("),
                      "body is not plain text with the name: \(body)")
        var mentioned = false
        for _ in 0..<20 where !mentioned {
            mentioned = (try? anna.hasMention(containing: "Bild \(stamp)")) ?? false
            if !mentioned { sleep(1) }
        }
        XCTAssertTrue(mentioned, "Anna got no mention")
        sleep(2)
        attach(app, "caption-mention-timeline")
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

    /// A GIF pasted from a keyboard app or copied in Safari arrives animated (Thorsten, 2026-11-19).
    /// Gboard and Safari put a still JPEG beside the GIF on the pasteboard; the JPEG used to win.
    func testPastedGifIsSentAsAGif() throws {
        let app = try openChannel()
        let before = Date()
        UIPasteboard.general.items = [[UTType.gif.identifier: try gifData(), UTType.jpeg.identifier: try stillJPEG()]]
        let composer = app.textViews["room-message_composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeKey("v", modifierFlags: .command)
        let caption = app.textViews["Bildunterschrift hinzufügen"]
        XCTAssertTrue(caption.waitForExistence(timeout: 60), "the paste opened no upload preview")
        attach(app, "gif-paste-preview")
        app.buttons.matching(NSPredicate(format: "label == 'Senden' AND identifier != 'room-send_button'")).firstMatch.tap()
        let event = try latestOwnMessage(msgtype: "m.image", after: before)
        let info = event["info"] as? [String: Any] ?? [:]
        XCTAssertEqual(info["mimetype"] as? String, "image/gif", "the pasted GIF was sent as \(info["mimetype"] ?? "nothing"): \(event)")
    }

    /// Eight coloured frames, an endless loop: an animated GIF as Gboard copies one.
    private func gifData() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 8, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<8 {
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
                UIColor(hue: CGFloat(index) / 8, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(frame.cgImage),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func stillJPEG() throws -> Data {
        try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }.jpegData(compressionQuality: 0.8))
    }

    /// "Markieren" in the upload preview opens a PencilKit canvas over the photo; the marked-up
    /// photo is what is sent (Thorsten, 2026-11-19; PencilKit approved 2026-11-20).
    func testPhotoMarkupIsSent() throws {
        let app = try openChannel()
        let before = Date()
        app.buttons["composer_toolbar-open_compose_options"].tap()
        let photos = app.buttons["room-attachment_picker_photo_library"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5), "no Fotos in the + menu")
        photos.tap()
        // build.sh's photo dated 2001-01-01, not a GIF other tests saved: Markieren is for
        // photos only, and only that date puts "2001" in the picker's label.
        let picture = app.images.matching(NSPredicate(format: "label CONTAINS '2001'")).firstMatch
        // The picker shows the newest pictures first; this one, the oldest, is further down.
        // Swipe up only: a swipe down closes the picker sheet.
        let anyPicture = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Foto' OR label BEGINSWITH 'Photo'")).firstMatch
        XCTAssertTrue(anyPicture.waitForExistence(timeout: 45), "the photo picker did not open")
        for _ in 0..<15 where !picture.isHittable {
            app.swipeUp(velocity: .fast)
            _ = picture.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(picture.isHittable, "photo picker shows no photo from 2001 (build.sh adds it)")
        sleep(1)
        picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Add"].tap()
        XCTAssertTrue(app.textViews["Bildunterschrift hinzufügen"].waitForExistence(timeout: 60), "no upload preview")

        let markup = app.buttons["upload.markup"]
        XCTAssertTrue(markup.waitForExistence(timeout: 10), "no Markieren in the upload preview")
        markup.tap()
        // Our PencilKit editor: a red stroke across the photo, then Fertig. The canvas is a
        // scroll view to XCTest, so it is looked up by identifier alone.
        let canvas = app.descendants(matching: .any)["markup.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Markieren opened no drawing canvas")
        let finish = app.buttons["markup.done"]
        XCTAssertFalse(finish.isEnabled, "Fertig is on before anything is drawn")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6)))
        attach(app, "markup-drawn")
        XCTAssertTrue(finish.isEnabled, "the stroke did not reach the canvas")
        finish.tap()
        XCTAssertTrue(app.textViews["Bildunterschrift hinzufügen"].waitForExistence(timeout: 20), "not back in the upload preview")
        attach(app, "markup-preview")
        app.buttons.matching(NSPredicate(format: "label == 'Senden' AND identifier != 'room-send_button'")).firstMatch.tap()
        let event = try latestOwnMessage(msgtype: "m.image", after: before)
        let mxc = try XCTUnwrap(event["url"] as? String, "the marked-up photo was not sent: \(event)")
        // The photo has no red; the pen draws red. Red pixels in what the server holds prove
        // the drawing went out, not the untouched photo.
        let sent = try XCTUnwrap(UIImage(data: try TestServer.signIn(1).download(mxc)), "the sent photo does not decode")
        XCTAssertGreaterThan(Self.redPixels(in: sent), 200, "the sent photo carries no drawing")
    }

    /// Pixels that are clearly red, the pen's colour.
    private static func redPixels(in image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 190 && pixels[$0 + 1] < 90 && pixels[$0 + 2] < 90 }.count
    }

    /// + › Fotos, the first library picture, Senden in the upload preview; returns the server's event.
    private func sendPhoto(_ app: XCUIApplication, shotPrefix: String = "",
                           caption typed: String? = nil, mention pick: String? = nil) throws -> [String: Any] {
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
        if let typed {
            caption.tap()
            caption.typeText(typed)
            if let pick {
                // The caption's @ suggestions, as in the message composer.
                let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", pick)).firstMatch
                XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "no @ suggestion for \(pick) in the caption")
                attach(app, shotPrefix + "caption-suggestion")
                suggestion.tap()
            }
        }
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
    /// Inside the window, by its frame. Not isHittable: for a row the list has laid out off
    /// screen, XCTest fails the test with "Failed to determine hittability" instead of answering
    /// false (CI, #54 and #56, 2026-11-21).
    private func onScreen(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && app.windows.firstMatch.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

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
