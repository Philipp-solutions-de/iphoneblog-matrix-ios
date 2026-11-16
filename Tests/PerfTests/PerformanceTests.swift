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

    private func app(member: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        let fixture = env["IPHONEBLOG_FIXTURE"] ?? "http://127.0.0.1:8796"
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

    /// Blog → #one-Chat → @Mentions → Ich → Blog, each until the tab's content shows.
    func testSwitchTabs() throws {
        let app = try app()
        launchSignedIn(app)
        _ = try openOneChat(app)
        measure(metrics: [XCTClockMetric(), XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
            for name in ["Blog", "#one-Chat", "@Mentions", "Ich", "Blog"] {
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
        // text: a CI runner's simulator hides WebKit's content from XCUITest.
        let pages = web.otherElements.matching(NSPredicate(format: "label MATCHES %@", "Vertical scroll bar, ([2-9]|[1-9][0-9]+) pages")).firstMatch
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
    private func allowLocalNetwork() {
        #if !targetEnvironment(simulator)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Erlauben", "Allow"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap(); return }
        }
        #endif
    }

    /// Opens the #one-Chat tab and returns its timeline once the newest seeded messages show.
    private func openOneChat(_ app: XCUIApplication) throws -> XCUIElement {
        allowLocalNetwork()
        let tab = tabButton(app, "#one-Chat")
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no #one-Chat tab")
        // The sign-in runs in the background after launch; the tab shows the channel once the
        // session and the space are there.
        // Two minutes: a CI runner's simulator signs in and syncs slowly.
        let deadline = Date().addingTimeInterval(120)
        // #one-Chat lists #one's rooms; Allgemein, the first, holds the seeded history.
        let room = app.buttons.matching(identifier: "one-room").firstMatch
        repeat {
            tab.tap()
            if room.waitForExistence(timeout: 5) { room.tap() }
            if app.staticTexts["Felix H."].firstMatch.waitForExistence(timeout: 5) { break }
        } while Date() < deadline
        if !app.staticTexts["Felix H."].firstMatch.exists {
            print("PERF-HIERARCHY-BEGIN\n\(app.debugDescription)\nPERF-HIERARCHY-END")
            XCTFail("#one-Chat shows no seeded messages")
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
        // The only thread in the channel with more than one reply. Its count is what the
        // app has loaded, not always 90, so match the form, not the number.
        let summary = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ Antworten")).firstMatch
        // A CI runner pages older messages in slowly: more swipes, each given a moment.
        for _ in 0..<25 where !summary.isHittable {
            list.swipeDown(velocity: .slow)
            _ = summary.waitForExistence(timeout: 1)
        }
        guard summary.isHittable else {
            // What the screen holds instead, for whoever reads the log.
            print("PERF-HIERARCHY-BEGIN\n\(app.debugDescription)\nPERF-HIERARCHY-END")
            XCTFail("no \"NN Antworten\" in #one-Chat")
            throw XCTSkip("thread summary not found")
        }
        return summary
    }
}
