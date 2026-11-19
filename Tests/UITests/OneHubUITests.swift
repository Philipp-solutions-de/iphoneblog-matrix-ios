import XCTest

/// The #one hub (variant A, spec-ios.md "Tests"): the newest episode unwatched and started, Chat
/// from the tile and from a "Gerade aktiv" row, Videos, the episode page and its player, and
/// progress kept after a relaunch. Episodes come from the bundled fixture; with
/// IPHONEBLOG_EPISODES_LOCAL_VIDEO=1 they play the bundled sample.
final class OneHubUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private let newest = "iphoneblog_one_527_kalenderwochen"

    override func setUp() {
        continueAfterFailure = false
    }

    func testHubShowsAnUnwatchedAndAStartedEpisode() throws {
        var app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1"])
        let hero = app.buttons["hub.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 120), "no Neu für dich")
        XCTAssertTrue(app.staticTexts["Neu für dich"].exists)
        XCTAssertTrue(hero.label.contains("Fokus-Modi, die wirklich helfen"), hero.label)
        XCTAssertTrue(hero.label.contains("Ansehen"), "an unwatched episode does not say Ansehen: \(hero.label)")
        XCTAssertTrue(app.descendants(matching: .any)["episode.new"].exists, "no Neu badge on an unwatched episode")
        XCTAssertTrue(app.buttons["hub.tile.chat"].exists && app.buttons["hub.tile.videos"].exists, "tiles missing")
        XCTAssertTrue(app.buttons["hub.tile.videos"].label.contains("525"), app.buttons["hub.tile.videos"].label)
        save(app, "hub-unwatched")
        app.terminate()

        app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=372/1532"])
        XCTAssertTrue(app.buttons["hub.hero"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["hub.hero"].label.contains("Weiter ab 6:12"), app.buttons["hub.hero"].label)
        XCTAssertTrue(app.descendants(matching: .any)["episode.progress"].exists, "no progress bar on a started episode")
        XCTAssertFalse(app.descendants(matching: .any)["episode.new"].exists, "Neu on a started episode")
        save(app, "hub-started")
    }

    func testChatFromTheTileAndFromAnActiveRow() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        try other.send("Hub aktiv \(Int(Date().timeIntervalSince1970))", in: room)

        let app = try launch([:])
        let tile = app.buttons["hub.tile.chat"]
        XCTAssertTrue(tile.waitForExistence(timeout: 120), "no Chat tile")
        XCTAssertTrue(tile.label.contains("Räume"), tile.label)
        tile.tap()
        XCTAssertTrue(app.scrollViews["one.roomBar"].waitForExistence(timeout: 30) || app.descendants(matching: .any)["one.roomBar"].exists,
                      "the tile does not open Chat with its room bar")
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 60), "no room in Chat")
        save(app, "hub-chat")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "back does not return to the hub")

        // The room just written to is on top of Gerade aktiv; its row opens that room.
        let row = app.buttons["hub.active.Allgemein"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Allgemein is not under Gerade aktiv")
        row.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Allgemein"].waitForExistence(timeout: 60), "the row does not land in Allgemein")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["hub.active.all"].waitForExistence(timeout: 10))
        app.buttons["hub.active.all"].tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 30), "Alle does not open Chat")
    }

    func testVideosListsEveryEpisodeWithItsState() throws {
        let app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=372/1532;gw-213-kurzbefehle=1000/1000"])
        let tile = app.buttons["hub.tile.videos"]
        XCTAssertTrue(tile.waitForExistence(timeout: 120))
        tile.tap()
        XCTAssertTrue(app.staticTexts["videos.subtitle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["videos.subtitle"].label, "Gewusst wie · 525 Folgen")
        let rows = app.buttons.matching(identifier: "videos.row")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 10), "fewer than three rows")
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Folge 527") && rows.element(boundBy: 0).label.contains("Weiter ab 6:12"),
                      rows.element(boundBy: 0).label)
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("Gesehen"), rows.element(boundBy: 1).label)
        XCTAssertTrue(rows.element(boundBy: 2).label.contains("Folge 525"), rows.element(boundBy: 2).label)
        save(app, "videos")
        rows.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["episode.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["episode.title"].label, "Live vom Apple-Event")
    }

    /// The page: title, notes, the poster with play; playing shows the drawn captions; leaving
    /// and coming back after a relaunch reads "Weiter ab".
    func testEpisodePagePlaysWithCaptionsAndKeepsProgress() throws {
        var app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_EPISODES_LOCAL_VIDEO": "1"])
        XCTAssertTrue(app.buttons["hub.hero"].waitForExistence(timeout: 120))
        app.buttons["hub.hero"].tap()
        XCTAssertTrue(app.staticTexts["episode.title"].waitForExistence(timeout: 10), "no episode page")
        XCTAssertEqual(app.staticTexts["episode.title"].label, "Fokus-Modi, die wirklich helfen")
        let notes = app.staticTexts["episode.notes"]
        XCTAssertTrue(notes.exists && notes.label.contains("Fokus-Modi") && notes.label.contains("• Schlafen"), "notes: \(notes.label)")
        XCTAssertFalse(notes.label.contains("<p>"), "HTML tags in the notes")
        save(app, "episode-poster")

        app.buttons["episode.play"].tap()
        let caption = app.staticTexts["player.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "no caption over the picture")
        XCTAssertTrue(caption.label.contains("Gewusst wie") || caption.label.contains("Fokus-Modi"), caption.label)
        // Speed and captions under the picture.
        app.buttons["player.speed"].tap()
        XCTAssertTrue(app.buttons["player.speed"].label.contains("1,25×"), app.buttons["player.speed"].label)
        app.buttons["player.captions"].tap()
        XCTAssertTrue(caption.waitForNonExistence(timeout: 5), "UT does not hide the captions")
        app.buttons["player.captions"].tap()
        app.buttons["player.forward"].tap()
        sleep(3)
        save(app, "episode-playing")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["hub.hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["hub.hero"].label.contains("Weiter ab 0:"), app.buttons["hub.hero"].label)
        app.terminate()

        // A relaunch keeps where it stopped.
        app = try launch(["IPHONEBLOG_EPISODES_LOCAL_VIDEO": "1"])
        XCTAssertTrue(app.buttons["hub.hero"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["hub.hero"].label.contains("Weiter ab 0:"), "progress lost after relaunch: \(app.buttons["hub.hero"].label)")
        app.buttons["hub.hero"].tap()
        XCTAssertTrue(app.staticTexts["episode.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["episode.status"].label.hasPrefix("Weiter ab 0:"), app.staticTexts["episode.status"].label)
        XCTAssertTrue(app.buttons["episode.play"].label.hasPrefix("Weiter ab"), app.buttons["episode.play"].label)
    }

    // MARK: - Helpers

    private func launch(_ extra: [String: String]) throws -> XCUIApplication {
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], !server.isEmpty else { throw XCTSkip("no test homeserver configured") }
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_NO_PUSH_PROMPT": "1", "IPHONEBLOG_START_TAB": "chat", "IPHONEBLOG_START_HUB": "1",
            "IPHONEBLOG_EPISODES_FIXTURE": "1",
            "IPHONEBLOG_HOMESERVER": server,
            "IPHONEBLOG_DEV_USER": env["IPHONEBLOG_TEST_USER"] ?? "", "IPHONEBLOG_DEV_PASSWORD": env["IPHONEBLOG_TEST_PASSWORD"] ?? "",
            "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "", "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
            "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
        ].merging(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
