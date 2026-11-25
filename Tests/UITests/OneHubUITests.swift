import XCTest

/// #one's start screen, draft B (Thorsten, 2026-11-20): the cover flow's episode states, the room
/// and Threads rows, Videos, the episode page and its player, and progress kept after a
/// relaunch; screenshots in light and dark. Episodes come from the bundled fixture; with
/// IPHONEBLOG_EPISODES_LOCAL_VIDEO=1 they play the bundled sample.
final class OneHubUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private let newest = "iphoneblog_one_527_kalenderwochen"

    override func setUp() {
        continueAfterFailure = false
    }

    /// The cover flow's first card: unwatched with "Neu", started with "Weiter ab" and the bar,
    /// watched with "Gesehen".
    func testCoverFlowShowsEachEpisodesState() throws {
        var app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1"])
        var first = app.buttons.matching(identifier: "one.episode").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120), "no episodes in the cover flow")
        XCTAssertTrue(app.staticTexts["Videos"].exists && app.staticTexts["Räume"].exists, "Videos or Räume missing")
        XCTAssertTrue(first.label.contains("Fokus-Modi, die wirklich helfen"), first.label)
        XCTAssertTrue(app.descendants(matching: .any)["episode.new"].exists, "no Neu badge on an unwatched episode")
        for gone in ["Neu für dich", "Bereiche", "Gerade aktiv"] {
            XCTAssertFalse(app.staticTexts[gone].exists, "the old hub's \(gone) is still there")
        }
        save(app, "one-light")
        app.terminate()

        app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=372/1532"])
        first = app.buttons.matching(identifier: "one.episode").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120))
        XCTAssertTrue(first.label.contains("Weiter ab 6:12"), first.label)
        XCTAssertTrue(app.descendants(matching: .any)["episode.progress"].exists, "no progress bar on a started episode")
        app.terminate()

        // Watched to 95 %: "Gesehen", as the Videos list says.
        app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=1500/1532"])
        first = app.buttons.matching(identifier: "one.episode").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120))
        XCTAssertTrue(first.label.contains("Gesehen"), "a watched episode does not say Gesehen: \(first.label)")
    }

    /// Every #one screen in light and dark, for the PR: the start screen at rest and swiped, a
    /// room, a thread, the Threads list, Videos and the episode page. #one is in the #one red,
    /// never teal (Thorsten, 2026-11-20): above the tab bar, which is not #one's, no screen may
    /// show a teal pixel.
    func testOneScreensInLightAndDarkWithoutTeal() throws {
        // The app's own switch: XCUIDevice.appearance left the simulator light (2026-11-20).
        for name in ["light", "dark"] {
            let app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=372/1532",
                                  "IPHONEBLOG_APPEARANCE": name])
            let flow = app.descendants(matching: .any)["one.coverflow"]
            XCTAssertTrue(flow.waitForExistence(timeout: 120), "no cover flow")
            sleep(2)
            check(app, "one-\(name)")
            XCTAssertTrue(tabColour(app, "one") == .red, "the selected one tab is not red (\(name))")
            flow.swipeLeft(velocity: .slow)
            sleep(1)
            check(app, "one-\(name)-swiped")

            let room = app.buttons["one.room.Allgemein"]
            XCTAssertTrue(room.waitForExistence(timeout: 10))
            room.tap()
            XCTAssertTrue(app.textViews["Nachricht an # Allgemein"].waitForExistence(timeout: 60), "no room")
            sleep(2)
            check(app, "one-\(name)-room")
            let summary = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Antwort'")).firstMatch
            if summary.waitForExistence(timeout: 5) {
                summary.tap()
                if app.textViews["Antworten…"].waitForExistence(timeout: 20) {
                    sleep(2)
                    check(app, "one-\(name)-thread")
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
            app.navigationBars.buttons.firstMatch.tap()

            let threads = app.buttons["one.threads"]
            if threads.waitForExistence(timeout: 10) {
                threads.tap()
                sleep(2)
                check(app, "one-\(name)-threads")
                app.navigationBars.buttons.firstMatch.tap()
            }

            app.buttons["one.videos.all"].tap()
            XCTAssertTrue(app.buttons.matching(identifier: "videos.row").firstMatch.waitForExistence(timeout: 10))
            check(app, "one-\(name)-videos")
            app.buttons.matching(identifier: "videos.row").firstMatch.tap()
            XCTAssertTrue(app.staticTexts["episode.title"].waitForExistence(timeout: 10))
            check(app, "one-\(name)-episode")
            // Outside #one the selected tab is teal again.
            app.tabBars.buttons["Blog"].tap()
            sleep(1)
            XCTAssertTrue(tabColour(app, "Blog") == .teal, "the selected Blog tab is not teal (\(name))")
            app.terminate()
        }
    }

    private enum Hue { case red, teal, neither }

    /// The colour of a tab item's coloured pixels: the selected item carries the tint.
    private func tabColour(_ app: XCUIApplication, _ label: String) -> Hue {
        guard let image = app.tabBars.buttons[label].firstMatch.screenshot().image.cgImage else { return .neither }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .neither }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var red = 0, teal = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), delta = maxC - min(r, g, b)
            guard maxC > 0.25, delta / maxC > 0.35 else { continue }
            if maxC == r { red += 1 } else if g > r && b > r { teal += 1 }
        }
        if red > 20 && red > teal * 3 { return .red }
        if teal > 20 && teal > red * 3 { return .teal }
        return .neither
    }

    /// Saves the screen and counts teal above the tab bar: hue 165–195°, clearly coloured.
    /// Pictures in messages are left out: their colours are the sender's, not the app's, and
    /// the room holds what earlier tests sent (a GIF with a cyan frame; 2026-11-25, shard 4).
    private func check(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        save(app, name)
        // Asked after the shot, and 4 pt wider: the timeline may still move a little, and a
        // picture scrolled under the room bar left its last two pixel rows (2026-11-26).
        let pictures = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-image.'"))
            .allElementsBoundByIndex.map { $0.frame.insetBy(dx: -4, dy: -4) }
        guard let image = shot.image.cgImage else { return }
        let width = image.width, height = image.height
        let scale = CGFloat(width) / app.frame.width
        let masked = pictures.map { CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The tab bar floats over the bottom eighth; its "one" is the app's, not #one's.
        let bottom = height * 7 / 8
        var teal = 0
        for y in stride(from: 0, to: bottom, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                if masked.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { continue }
                let i = (y * width + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
                guard maxC > 0.25, delta / maxC > 0.35 else { continue }
                var hue: Double
                if maxC == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                else if maxC == g { hue = 60 * ((b - r) / delta + 2) }
                else { hue = 60 * ((r - g) / delta + 4) }
                if hue < 0 { hue += 360 }
                if hue >= 165 && hue <= 195 { teal += 1 }
            }
        }
        XCTAssertLessThan(teal, 40, "\(name): \(teal) teal pixels inside #one")
    }

    /// A room row opens Chat on that room, with its newest message as the preview; the Threads
    /// row opens the Threads list.
    func testRoomsAndThreadsRows() throws {
        let other = try TestServer.signIn(2)
        addTeardownBlock { other.signOut() }
        let room = try XCTUnwrap(env["IPHONEBLOG_TEST_CHANNEL_ROOM"])
        let text = "Raumliste \(Int(Date().timeIntervalSince1970))"
        try other.send(text, in: room)

        let app = try launch([:])
        let row = app.buttons["one.room.Allgemein"]
        XCTAssertTrue(row.waitForExistence(timeout: 120), "no Allgemein under Räume")
        let deadline = Date().addingTimeInterval(30)
        while !row.label.contains(text), Date() < deadline { sleep(1) }
        XCTAssertTrue(row.label.contains(text), "the row does not show the newest message: \(row.label)")
        row.tap()
        XCTAssertTrue(app.textViews["Nachricht an # Allgemein"].waitForExistence(timeout: 60), "the row does not open Allgemein")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "back does not return to #one")

        let threads = app.buttons["one.threads"]
        if threads.waitForExistence(timeout: 10) {
            threads.tap()
            XCTAssertTrue(app.navigationBars["Threads"].waitForExistence(timeout: 10), "the Threads row does not open the list")
        }
    }

    func testVideosListsEveryEpisodeWithItsState() throws {
        let app = try launch(["IPHONEBLOG_PLAYBACK_RESET": "1", "IPHONEBLOG_PLAYBACK_SEED": "\(newest)=372/1532;gw-213-kurzbefehle=1000/1000"])
        let all = app.buttons["one.videos.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 120))
        all.tap()
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
        let first = app.buttons.matching(identifier: "one.episode").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 120))
        first.tap()
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
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("Weiter ab 0:"), first.label)
        app.terminate()

        // A relaunch keeps where it stopped.
        app = try launch(["IPHONEBLOG_EPISODES_LOCAL_VIDEO": "1"])
        let again = app.buttons.matching(identifier: "one.episode").firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 120))
        XCTAssertTrue(again.label.contains("Weiter ab 0:"), "progress lost after relaunch: \(again.label)")
        again.tap()
        XCTAssertTrue(app.staticTexts["episode.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["episode.status"].label.hasPrefix("Weiter ab 0:"), app.staticTexts["episode.status"].label)
        XCTAssertTrue(app.buttons["episode.play"].label.hasPrefix("Weiter ab"), app.buttons["episode.play"].label)
    }

    // MARK: - Helpers

    /// A back swipe let go halfway keeps the back button where the system puts it: the hub has a
    /// navigation bar too, so the bar does not appear and vanish with the swipe (Philip,
    /// 2026-11-20: the arrow jumped to the screen's edge). The shots during the snap back show
    /// it; the test checks that the swipe returns to Chat and a full swipe reaches #one.
    func testBackSwipeLetGoStaysInChat() throws {
        let app = try launch([:])
        let tile = app.buttons["one.room.Allgemein"]
        XCTAssertTrue(tile.waitForExistence(timeout: 120), "no Allgemein row")
        sleep(1)
        save(app, "root-hub")
        // The Blog tab's root: its logo bar must look as it did (Brain, 2026-11-20).
        let blogTab = app.buttons["Blog"].firstMatch
        if blogTab.exists {
            blogTab.tap()
            sleep(5)
            save(app, "root-blog")
            app.tabBars.buttons["one"].firstMatch.tap()
            XCTAssertTrue(tile.waitForExistence(timeout: 10), "back on #one, no Allgemein row")
        }
        tile.tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 60), "no room in Chat")
        sleep(1)
        save(app, "backswipe-rest")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        for index in 0..<4 { save(app, "backswipe-letgo-\(index)") }
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 5), "a half swipe left Chat")
        sleep(1)
        edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)),
                   withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "a full back swipe does not return to #one")
        save(app, "backswipe-hub")
    }

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
