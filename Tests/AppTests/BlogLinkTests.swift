import XCTest
@testable import iphoneblog

/// The Blog tab's web view rules and the article → thread lookup (WordPress PR #274,
/// 2026-11-14_interfaces.md "Blog app view" and "Matrix at chat.iphoneblog.de").
final class BlogLinkTests: XCTestCase {
    private let hosts: Set<String> = ["iphoneblog.de", "www.iphoneblog.de", "beta.iphoneblog.de"]

    private func decide(_ string: String, mainFrame: Bool = true) -> BlogNavigation {
        BlogNavigation.decide(URL(string: string)!, mainFrame: mainFrame, blogHosts: hosts)
    }

    // MARK: The "Diskussion" link

    func testDiscussionLinkIsInterceptedWithItsPermalink() {
        let link = "iphoneblog-chat://diskussion?url=https%3A%2F%2Fbeta.iphoneblog.de%2F2026%2F11%2F15%2Fkw-46%2F"
        XCTAssertEqual(decide(link), .discussion(URL(string: "https://beta.iphoneblog.de/2026/11/15/kw-46/")!))
    }

    func testDiscussionLinkFromAnIframeIsInterceptedToo() {
        let link = "iphoneblog-chat://diskussion?url=https%3A%2F%2Fwww.iphoneblog.de%2Fa%2F"
        XCTAssertEqual(decide(link, mainFrame: false), .discussion(URL(string: "https://www.iphoneblog.de/a/")!))
    }

    func testMalformedDiscussionLinksAreIgnored() {
        XCTAssertEqual(decide("iphoneblog-chat://diskussion"), .ignore)
        XCTAssertEqual(decide("iphoneblog-chat://diskussion?url="), .ignore)
        XCTAssertEqual(decide("iphoneblog-chat://diskussion?url=javascript%3Aalert(1)"), .ignore)
        XCTAssertEqual(decide("iphoneblog-chat://other?url=https%3A%2F%2Fwww.iphoneblog.de%2Fa%2F"), .ignore)
    }

    // MARK: Blog pages keep app=1

    func testBlogPageWithFlagLoads() {
        XCTAssertEqual(decide("https://beta.iphoneblog.de/2026/11/15/kw-46/?app=1"), .allow)
    }

    func testBlogPageWithoutFlagReloadsWithIt() {
        XCTAssertEqual(decide("https://beta.iphoneblog.de/page/2/"),
                       .reload(URL(string: "https://beta.iphoneblog.de/page/2/?app=1")!))
        XCTAssertEqual(decide("https://www.iphoneblog.de/?s=iPad"),
                       .reload(URL(string: "https://www.iphoneblog.de/?s=iPad&app=1")!))
    }

    func testFlagIsNotDoubled() {
        let url = AppFlag.added(to: URL(string: "https://www.iphoneblog.de/?app=0&x=1")!)
        XCTAssertEqual(url.absoluteString, "https://www.iphoneblog.de/?x=1&app=1")
    }

    // MARK: Everything else leaves the app

    func testOtherSitesOpenInSafari() {
        XCTAssertEqual(decide("https://www.apple.com/de/iphone/"), .external(URL(string: "https://www.apple.com/de/iphone/")!))
        XCTAssertEqual(decide("https://chat.iphoneblog.de/"), .external(URL(string: "https://chat.iphoneblog.de/")!))
        XCTAssertEqual(decide("mailto:alex@iphoneblog.de"), .external(URL(string: "mailto:alex@iphoneblog.de")!))
    }

    func testStaffGateSignInStaysInTheWebView() {
        XCTAssertEqual(decide("https://auth.phso.de/api/oidc/authorization?client_id=edge"), .allow)
        // The gate's own callback on beta carries no app=1; it gets it and still lands.
        XCTAssertEqual(decide("https://beta.iphoneblog.de/oauth2/callback?code=x"),
                       .reload(URL(string: "https://beta.iphoneblog.de/oauth2/callback?code=x&app=1")!))
    }

    func testEmbedsLoadInsideThePage() {
        XCTAssertEqual(decide("https://www.youtube-nocookie.com/embed/x", mainFrame: false), .allow)
    }

    // MARK: Article → thread, by path

    func testPathKeyIgnoresHostQueryAndTrailingSlash() {
        let keys = [
            "https://www.iphoneblog.de/2026/11/15/kw-46/",
            "https://beta.iphoneblog.de/2026/11/15/kw-46/?app=1",
            "https://beta.iphoneblog.de/2026/11/15/kw-46#comments",
            "https://iphoneblog.de/2026/11/15/KW-46/",
        ].map { ArticlePath.key(URL(string: $0)!) }
        XCTAssertEqual(Set(keys), ["/2026/11/15/kw-46/"])
    }

    func testHomePageHasNoKey() {
        XCTAssertNil(ArticlePath.key(URL(string: "https://www.iphoneblog.de/")!))
        XCTAssertNil(ArticlePath.key(URL(string: "https://www.iphoneblog.de")!))
    }

    func testPercentEncodedSlugsMatch() {
        let encoded = URL(string: "https://beta.iphoneblog.de/2026/11/15/k%C3%A4se/")!
        let index = BlogLinkIndex(roots: ["https://www.iphoneblog.de/2026/11/15/k%C3%A4se/": "$k"])
        XCTAssertEqual(index.rootEventID(for: encoded), "$k")
    }

    func testLinksJSONFindsTheThreadForABetaPermalink() throws {
        let json = #"{"generated_ts":1763200200000,"links":{"https://www.iphoneblog.de/2026/11/15/kw-46/":"$root46","https://www.iphoneblog.de/2026/11/14/breakfast/":"$rootB"}}"#
        let index = try BlogLinkIndex(json: Data(json.utf8))
        XCTAssertEqual(index.rootEventID(for: URL(string: "https://beta.iphoneblog.de/2026/11/15/kw-46/")!), "$root46")
        XCTAssertEqual(index.rootEventID(for: URL(string: "https://www.iphoneblog.de/2026/11/14/breakfast/?app=1")!), "$rootB")
        XCTAssertNil(index.rootEventID(for: URL(string: "https://www.iphoneblog.de/2026/11/13/other/")!))
    }

    // MARK: The Blog tab's navigation stack

    func testRoutesRoundTripThroughRouterStrings() {
        let article = BlogRoute.article(URL(string: "https://beta.iphoneblog.de/2026/11/15/kw-46/")!)
        XCTAssertEqual(BlogRoute(article.value), article)
        XCTAssertEqual(BlogRoute("$abc:iphoneblog.de"), .thread(rootEventID: "$abc:iphoneblog.de"))
        XCTAssertNil(BlogRoute("nonsense"))
    }

    func testPageTitleLosesTheSiteName() {
        XCTAssertEqual(DiscussionView.trimSiteName("Kalenderwoche 46 – iPhoneBlog.de"), "Kalenderwoche 46")
        XCTAssertEqual(DiscussionView.trimSiteName("Ohne Trenner"), "Ohne Trenner")
    }

    func testReplyTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 13))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10, minute: 42))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 11, minute: 48))!
        XCTAssertTrue(DiscussionTime.text(today, now: now, calendar: calendar).hasSuffix(":42"))
        XCTAssertTrue(DiscussionTime.text(yesterday, now: now, calendar: calendar).hasPrefix("Gestern, "))
    }
}
