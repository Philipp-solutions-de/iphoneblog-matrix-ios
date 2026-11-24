import XCTest

/// "GIFs aus dem Chat" (gif-library.md): the + menu opens the library, a tap sends the GIF by its
/// mxc into the room or thread, a long press edits tags or reports. The library is the fixture
/// server's stand-in (scripts/blog-fixture-server.py, /gifs), the GIF itself a real upload on
/// the test homeserver, so the sent message and its thumbnail are real.
final class GIFPickerUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8793" }

    override func setUp() {
        continueAfterFailure = false
    }

    func testATappedGIFGoesIntoTheRoom() throws {
        let me = try TestServer.signIn(1)
        defer { me.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let mxc = try library(me, tagged: ["jubeln"], untagged: true)

        let app = launch(["IPHONEBLOG_START_ROOM": room])
        openPicker(app)
        let tiles = app.buttons.matching(identifier: "gif-picker.tile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 20), "no GIFs in the picker")
        XCTAssertEqual(tiles.count, 2)
        XCTAssertTrue(app.buttons["GIF ohne Schlagworte"].exists, "the untagged GIF is not marked")
        attach(app, "gif-picker")

        app.buttons["GIF: jubeln"].tap()
        let sent = try XCTUnwrap(try me.image(in: room, mxc: mxc), "the GIF did not go into the room")
        XCTAssertEqual(sent["msgtype"] as? String, "m.image")
        XCTAssertEqual((sent["info"] as? [String: Any])?["mimetype"] as? String, "image/gif")
    }

    func testAGIFPickedInAThreadGoesIntoTheThread() throws {
        let me = try TestServer.signIn(1)
        defer { me.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let root = try me.send("GIF-Thread \(Int.random(in: 1000...9999))", in: room)
        let mxc = try library(me, tagged: ["facepalm"], untagged: false)

        let app = launch(["IPHONEBLOG_START_THREAD": "\(room)|\(root)"])
        openPicker(app)
        XCTAssertTrue(app.buttons["GIF: facepalm"].waitForExistence(timeout: 20), "no GIF in the picker")
        app.buttons["GIF: facepalm"].tap()
        let sent = try XCTUnwrap(try me.image(in: room, mxc: mxc), "the GIF was not sent")
        let relation = sent["m.relates_to"] as? [String: Any]
        XCTAssertEqual(relation?["rel_type"] as? String, "m.thread", "the GIF did not go into the thread")
        XCTAssertEqual(relation?["event_id"] as? String, root)
    }

    func testALongPressEditsTagsAndReports() throws {
        let me = try TestServer.signIn(1)
        defer { me.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        _ = try library(me, tagged: ["jubeln"], untagged: true)
        let before = try fixtureCalls()

        let app = launch(["IPHONEBLOG_START_ROOM": room])
        openPicker(app)
        let untagged = app.buttons["GIF ohne Schlagworte"]
        XCTAssertTrue(untagged.waitForExistence(timeout: 20))

        untagged.press(forDuration: 1.2)
        app.buttons["Schlagworte bearbeiten"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no tag field")
        field.typeText("Kaffee, Montag")
        app.alerts.buttons["Speichern"].tap()
        XCTAssertTrue(app.buttons["GIF: kaffee, montag"].waitForExistence(timeout: 10), "the new tags do not show")
        XCTAssertEqual(try fixtureState()["last_tags"] as? [String], ["kaffee", "montag"])

        app.buttons["GIF: jubeln"].press(forDuration: 1.2)
        app.buttons["Melden"].tap()
        let confirm = app.sheets.buttons["Melden"].exists ? app.sheets.buttons["Melden"] : app.buttons.matching(identifier: "Melden").element(boundBy: 0)
        confirm.tap()
        XCTAssertTrue(app.buttons["GIF: jubeln"].waitForNonExistence(timeout: 5), "the reported GIF stayed in the grid")
        XCTAssertEqual((try fixtureCalls()["gif_reports"] ?? 0) - (before["gif_reports"] ?? 0), 1)
        attach(app, "gif-picker-after-report")
    }

    // MARK: Helpers

    /// Uploads a GIF as the tester and lists it in the fixture's library: once tagged, and, when
    /// asked, once more without tags. Returns the tagged GIF's mxc.
    private func library(_ me: TestServer, tagged tags: [String], untagged: Bool) throws -> String {
        let mxc = try me.uploadGIF()
        var gifs: [[String: Any]] = [["id": String(repeating: "a", count: 64), "mxc": mxc, "width": 240, "height": 160,
                                      "size": 4000, "uses": 3, "tags": tags]]
        if untagged {
            gifs.append(["id": String(repeating: "b", count: 64), "mxc": try me.uploadGIF(width: 200, height: 200),
                         "width": 200, "height": 200, "size": 3000, "uses": 1, "tags": [String]()])
        }
        try post("/gifs-fixture", ["gifs": gifs])
        return mxc
    }

    private func launch(_ start: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat",
            "IPHONEBLOG_HOMESERVER": env["IPHONEBLOG_TEST_HOMESERVER"] ?? "",
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
            "IPHONEBLOG_GIFS_URL": "\(fixture)/gifs",
        ].merging(start) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 120), "the room did not open")
        return app
    }

    private func openPicker(_ app: XCUIApplication) {
        let plus = app.buttons["composer_toolbar-open_compose_options"]
        // The library's entry needs the #one rooms loaded; the menu is built when it opens.
        let entry = app.buttons["room-attachment_picker_gif_library"]
        for _ in 0..<5 {
            plus.tap()
            if entry.waitForExistence(timeout: 3) { break }
            app.swipeDown() // closes the menu
            sleep(3)
        }
        XCTAssertTrue(entry.exists, "no \"GIFs aus dem Chat\" in the + menu")
        entry.tap()
        XCTAssertTrue(app.navigationBars["GIFs aus dem Chat"].waitForExistence(timeout: 10), "the picker did not open")
    }

    private func post(_ path: String, _ body: [String: Any]) throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: fixture + path)))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let done = XCTestExpectation(description: path)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    private func fixtureCalls() throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: XCTUnwrap(URL(string: "\(fixture)/calls"))))
    }

    private func fixtureState() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(URL(string: "\(fixture)/gifs-state")))) as? [String: Any])
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
