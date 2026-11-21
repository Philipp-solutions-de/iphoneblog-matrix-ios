import XCTest

/// Scroll, open and launch timings, with hitch ratios, against the test homeserver's seeded
/// history (scripts/perf.sh, scripts/seed-perf-data.py; docs/performance.md).
///
/// Each test measures five iterations after one warm-up. `scripts/perf-gate.py` reads the
/// results and fails CI when a number is over its budget or worse than its baseline in
/// `scripts/perf-baseline.json` by more than the tolerance there. Xcode's own baselines are
/// tied to one machine's id and cannot follow GitHub's runners, so the gate keeps its own.
final class PerformanceTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private var options: XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }

    /// Where the app writes its frame totals: scripts/perf.sh passes a path under build/.
    private var statsPath: String {
        env["IPHONEBLOG_PERF_STATS"] ?? NSTemporaryDirectory() + "perf-stats.json"
    }

    private var fixture: String { env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8796" }

    private func app(member: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "IPHONEBLOG_BLOG_WEB": "\(fixture)/blog/?app=1",
            "IPHONEBLOG_BLOG_API": "\(fixture)/api",
            "IPHONEBLOG_NO_PUSH_PROMPT": "1",
            // The frame-rate readout, whose totals HitchMetric reads from this file.
            "IPHONEBLOG_FPS": "1",
            "IPHONEBLOG_PERF_STATS": statsPath,
        ]
        if member {
            guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
                  let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
                throw XCTSkip("no test homeserver configured (scripts/perf.sh)")
            }
            app.launchEnvironment.merge([
                "IPHONEBLOG_HOMESERVER": server,
                "IPHONEBLOG_DEV_USER": user,
                "IPHONEBLOG_DEV_PASSWORD": password,
                "IPHONEBLOG_ONE_ALIAS": env["IPHONEBLOG_ONE_ALIAS"] ?? "",
                "IPHONEBLOG_BLOG_ALIAS": env["IPHONEBLOG_BLOG_ALIAS"] ?? "",
                "IPHONEBLOG_CHANNEL_ALIAS": env["IPHONEBLOG_CHANNEL_ALIAS"] ?? "",
            ]) { _, new in new }
        } else {
            app.launchEnvironment["IPHONEBLOG_SIGNED_OUT"] = "1"
        }
        return app
    }

    // MARK: Launch

    /// Cold launch to the first frame that answers a touch, signed out (the Blog tab).
    func testLaunch() throws {
        let app = try app(member: false)
        // The clock as well: a CI runner's simulator does not always report the launch metric.
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTClockMetric()], options: options) {
            app.launch()
            app.terminate()
        }
    }

    // MARK: #one-Chat

    /// A launch with a stored session to the first message in #one, through a phone's round
    /// trip (latency-proxy.py, 100 ms). Start-up steps that wait one after another cost a round
    /// trip each: the room list, the bots, the name and the picture held the screens back by
    /// about a second (2026-11-20, docs/performance.md).
    func testOneChatAfterLaunch() throws {
        let app = try app()
        guard let slow = env["IPHONEBLOG_SLOW_HOMESERVER"] else { throw XCTSkip("no slow homeserver (scripts/perf.sh)") }
        app.launchEnvironment["IPHONEBLOG_HOMESERVER"] = slow
        app.launchEnvironment["IPHONEBLOG_START_TAB"] = "chat"
        let startFile = (statsPath as NSString).deletingLastPathComponent + "/perf-start.json"
        app.launchEnvironment["IPHONEBLOG_PERF_START"] = startFile
        // Signed in once outside the measurement: each measured launch restores that session.
        launchSignedIn(app)
        let message = app.staticTexts["Felix H."].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 120), "#one shows no seeded messages")
        app.terminate()
        let measured = XCTMeasureOptions()
        measured.iterationCount = 5
        measured.invocationOptions = [.manuallyStop]
        measure(metrics: [FirstMessagesMetric(path: startFile)], options: measured) {
            app.launch()
            XCTAssertTrue(message.waitForExistence(timeout: 60), "#one shows no seeded messages after a launch")
            sleep(1) // the app writes its time a moment after the timeline fills
            stopMeasuring()
            app.terminate()
        }
    }

    /// The channel with 160 messages, 30 of them photos up to 4032x3024: fling up through the
    /// history and back down.
    func testScrollOneChat() throws {
        let app = try app()
        launchSignedIn(app)
        let list = try openOneChat(app)
        // Load the history once outside the measurement, so the test measures scrolling, not the
        // network: up until the top, then back to the newest.
        for _ in 0..<12 { list.swipeDown(velocity: .fast) }
        for _ in 0..<12 { list.swipeUp(velocity: .fast) }
        measure(metrics: [HitchMetric(statsPath: statsPath), XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric],
                options: options) {
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
        }
    }

    /// From the channel into the long thread (90 replies, 12 photos) until its first replies show.
    func testOpenThread() throws {
        let app = try app()
        launchSignedIn(app)
        let list = try openOneChat(app)
        let summary = try threadSummary(app, in: list)
        measure(metrics: [XCTClockMetric(), XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
            summary.tap()
            XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 20), "thread did not open")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(summary.waitForExistence(timeout: 10))
        }
    }

    /// The long thread itself, flung down and up.
    func testScrollThread() throws {
        let app = try app()
        launchSignedIn(app)
        let list = try openOneChat(app)
        try threadSummary(app, in: list).tap()
        XCTAssertTrue(app.buttons["room-send_button"].waitForExistence(timeout: 20), "thread did not open")
        let thread = timeline(app)
        for _ in 0..<8 { thread.swipeDown(velocity: .fast) }
        for _ in 0..<8 { thread.swipeUp(velocity: .fast) }
        measure(metrics: [HitchMetric(statsPath: statsPath), XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric],
                options: options) {
            thread.swipeDown(velocity: .fast)
            thread.swipeDown(velocity: .fast)
            thread.swipeUp(velocity: .fast)
            thread.swipeUp(velocity: .fast)
        }
    }

    // MARK: Tabs

    /// Blog → #one → Für dich → Ich → Blog, each until the tab's content shows.
    func testSwitchTabs() throws {
        let app = try app()
        launchSignedIn(app)
        _ = try openOneChat(app)
        measure(metrics: [XCTClockMetric(), XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
            for name in ["Blog", "one", "Für dich", "Ich", "Blog"] {
                let tab = tabButton(app, name)
                tab.tap()
                XCTAssertTrue(tab.isSelected, "\(name) not selected")
            }
        }
    }

    // MARK: Blog

    /// The Blog tab's web view, flung down and up (the fixture's article list).
    func testScrollBlog() throws {
        let app = try app(member: false)
        app.launch()
        allowLocalNetwork()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20), "no blog web view")
        // The page has loaded when its scroll bar counts more than one page. Not the page's own
        // text: a CI runner's simulator hides WebKit's content from XCUITest. The app is German
        // only (CFBundleLocalizations), so WebKit says "Vertikaler Rollbalken, 7 Seiten".
        let pages = web.otherElements.matching(NSPredicate(format: "label MATCHES %@",
            "(Vertical scroll bar|Vertikaler Rollbalken), ([2-9]|[1-9][0-9]+) (pages|Seiten)")).firstMatch
        if !pages.waitForExistence(timeout: 60) {
            print("PERF-HIERARCHY-BEGIN\n\(app.debugDescription)\nPERF-HIERARCHY-END")
            XCTFail("blog page not loaded")
        }
        measure(metrics: [HitchMetric(statsPath: statsPath), XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric],
                options: options) {
            web.swipeUp(velocity: .fast)
            web.swipeUp(velocity: .fast)
            web.swipeDown(velocity: .fast)
            web.swipeDown(velocity: .fast)
        }
    }

    // MARK: Helpers

    /// Launches the member app with a fresh sign-in. Each run starts a new test server, and a
    /// device keeps the last run's session in its keychain, which the new server answers with
    /// 401. A signed-out launch first deletes it (AppModel.restore, IPHONEBLOG_SIGNED_OUT).
    private func launchSignedIn(_ app: XCUIApplication) {
        let reset = XCUIApplication()
        reset.launchEnvironment = ["IPHONEBLOG_SIGNED_OUT": "1", "IPHONEBLOG_NO_PUSH_PROMPT": "1"]
        reset.launch()
        reset.terminate()
        app.launch()
    }

    /// On a device, the first connection to the Mac's LAN address asks for local network access.
    // MARK: Search

    /// The search over blog and #one (ADR-0010): the fixture's 60 mixed hits with their marks,
    /// all three pages loaded, flung up and down. Every row's text and highlights are prepared
    /// off the main thread when the answer arrives; scrolling only lays them out.
    func testScrollSearch() throws {
        let app = try app(member: false)
        app.launchEnvironment["IPHONEBLOG_SEARCH_URL"] = "\(fixture)/_iphoneblog/v1/search"
        app.launch()
        allowLocalNetwork()
        let button = app.buttons["blog.search"]
        XCTAssertTrue(button.waitForExistence(timeout: 60), "no search in the Blog tab")
        button.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        // "Suchen" closes the keyboard, which would otherwise take the lower half's drags.
        field.typeText("akku\n")
        let hit = app.descendants(matching: .any).matching(identifier: "site-search-hit").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "no hits")
        // Drags from the window's own points, flung at 2500 pt/s. Down to the end first, so all three pages are in before the
        // measuring starts.
        func fling(_ from: CGFloat, _ to: CGFloat) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                       withVelocity: 2500, thenHoldForDuration: 0)
        }
        for _ in 0..<16 { fling(0.8, 0.3) }
        for _ in 0..<16 { fling(0.3, 0.8) }
        measure(metrics: [HitchMetric(statsPath: statsPath), XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric],
                options: options) {
            fling(0.8, 0.3)
            fling(0.8, 0.3)
            fling(0.3, 0.8)
            fling(0.3, 0.8)
        }
    }

    private func allowLocalNetwork() {
        #if !targetEnvironment(simulator)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Erlauben", "Allow"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap(); return }
        }
        #endif
    }

    /// Opens the #one tab and returns its timeline once the newest seeded messages show.
    private func openOneChat(_ app: XCUIApplication) throws -> XCUIElement {
        allowLocalNetwork()
        let tab = tabButton(app, "one")
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no #one tab")
        // The sign-in runs in the background after launch; the tab shows the channel once the
        // session and the space are there.
        // Two minutes: a CI runner's simulator signs in and syncs slowly.
        let deadline = Date().addingTimeInterval(120)
        // #one's room bar; Allgemein, the first room, holds the seeded history.
        let room = app.buttons.matching(identifier: "one-room").firstMatch
        // The tab opens on the hub; its chat tile leads to the rooms.
        let chatTile = app.buttons["hub.tile.chat"].firstMatch
        repeat {
            tab.tap()
            if chatTile.waitForExistence(timeout: 5) { chatTile.tap() }
            if room.waitForExistence(timeout: 5) { room.tap() }
            if app.staticTexts["Felix H."].firstMatch.waitForExistence(timeout: 5) { break }
        } while Date() < deadline
        if !app.staticTexts["Felix H."].firstMatch.exists {
            print("PERF-HIERARCHY-BEGIN\n\(app.debugDescription)\nPERF-HIERARCHY-END")
            XCTFail("#one shows no seeded messages")
        }
        return timeline(app)
    }

    /// A tab's button. An iPhone has a tab bar at the bottom; on an iPad, iPadOS draws the tabs
    /// at the top, outside any element XCUITest calls a tab bar.
    private func tabButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        if inBar.exists { return inBar }
        let anywhere = app.buttons.matching(identifier: name).firstMatch
        if anywhere.exists { return anywhere }
        return UIDevice.current.userInterfaceIdiom == .pad ? anywhere : inBar
    }

    /// The timeline's scroll view: Element X's is a collection view in the conversation.
    private func timeline(_ app: XCUIApplication) -> XCUIElement {
        let collection = app.collectionViews.firstMatch
        if collection.exists { return collection }
        let table = app.tables.firstMatch
        if table.exists { return table }
        return app.scrollViews.firstMatch
    }

    /// The long thread's "NN Antworten" under its root (scripts/seed-perf-data.py puts the root
    /// ten messages above the newest), scrolled into view.
    private func threadSummary(_ app: XCUIApplication, in list: XCUIElement) throws -> XCUIElement {
        // The only thread in allgemein with replies: its row under the root ("90 Antworten, …").
        let summary = app.buttons.matching(identifier: "thread-row").firstMatch
        // A CI runner pages older messages in slowly: more swipes, each given a moment. A swipe
        // can carry past the row while the list still moves, so the search also comes back up.
        for _ in 0..<25 where !summary.isHittable {
            list.swipeDown(velocity: .slow)
            _ = summary.waitForExistence(timeout: 1)
        }
        for _ in 0..<25 where !summary.isHittable {
            list.swipeUp(velocity: .slow)
            _ = summary.waitForExistence(timeout: 1)
        }
        guard summary.isHittable else {
            // What the screen holds instead, for whoever reads the log.
            print("PERF-HIERARCHY-BEGIN\n\(app.debugDescription)\nPERF-HIERARCHY-END")
            XCTFail("no thread row in allgemein")
            throw XCTSkip("thread summary not found")
        }
        return summary
    }
}
