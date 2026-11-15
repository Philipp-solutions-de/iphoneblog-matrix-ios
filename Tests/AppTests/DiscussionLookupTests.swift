import XCTest
@testable import iphoneblog

/// The "Diskussion" link and the article → thread lookup, beyond BlogLinksTests
/// (WordPress PR #274; 2026-11-14_interfaces.md, "Matrix at chat.iphoneblog.de").
final class DiscussionLookupTests: XCTestCase {
    private let beta = "beta.iphoneblog.de"

    private func classify(_ string: String) -> BlogLinks.Target {
        BlogLinks.classify(URL(string: string)!, blogHost: beta)
    }

    func testDiscussionLinkAsWordPressWritesIt() {
        // rawurlencode() of the permalink, with the serving host.
        XCTAssertEqual(classify("iphoneblog-chat://diskussion?url=https%3A%2F%2Fbeta.iphoneblog.de%2F2026%2F11%2F15%2Fkalenderwoche-46%2F"),
                       .discussion(URL(string: "https://beta.iphoneblog.de/2026/11/15/kalenderwoche-46/")!))
    }

    func testDiscussionLinkMustCarryAWebAddress() {
        XCTAssertEqual(classify("iphoneblog-chat://diskussion?url="), .ignore)
        XCTAssertEqual(classify("iphoneblog-chat://diskussion?url=javascript%3Aalert(1)"), .ignore)
        XCTAssertEqual(classify("iphoneblog-chat://diskussion?url=%2F2026%2F11%2F15%2Fx%2F"), .ignore)
        XCTAssertEqual(classify("iphoneblog-chat://anderes?url=https%3A%2F%2Fwww.iphoneblog.de%2Fa%2F"), .ignore)
    }

    func testAppViewFlagIsAddedOnce() {
        XCTAssertEqual(BlogLinks.withAppView(URL(string: "https://www.iphoneblog.de/?app=0&s=iPad")!).absoluteString,
                       "https://www.iphoneblog.de/?s=iPad&app=1")
        XCTAssertEqual(BlogLinks.withAppView(URL(string: "https://www.iphoneblog.de/?app=1")!).absoluteString,
                       "https://www.iphoneblog.de/?app=1")
    }

    func testKeyIgnoresHostQueryFragmentCaseAndSlashes() {
        let keys = [
            "https://www.iphoneblog.de/2026/11/15/kw-46/",
            "https://beta.iphoneblog.de/2026/11/15/kw-46/?app=1",
            "https://beta.iphoneblog.de/2026/11/15/kw-46#comments",
            "https://iphoneblog.de/2026/11/15/KW-46//",
        ].map { DiscussionStore.key(for: URL(string: $0)!) }
        XCTAssertEqual(Set(keys), ["/2026/11/15/kw-46/"])
    }

    func testPercentEncodedSlugMatchesEitherSpelling() throws {
        let json = #"{"generated_ts":1,"links":{"https://www.iphoneblog.de/2026/11/15/k%C3%A4se/":"$k"}}"#
        let index = DiscussionStore.index(try GuestAPI.decoder.decode(GuestAPI.Links.self, from: Data(json.utf8)))
        XCTAssertEqual(index[DiscussionStore.key(for: URL(string: "https://beta.iphoneblog.de/2026/11/15/k%C3%A4se/?app=1")!)], "$k")
    }

    func testLinksJSONFindsTheThreadForABetaPermalink() throws {
        let json = #"{"generated_ts":1794776091657,"links":{"https://www.iphoneblog.de/2026/11/15/kw-46/":"$root46","https://www.iphoneblog.de/2026/11/14/breakfast/":"$rootB"}}"#
        let index = DiscussionStore.index(try GuestAPI.decoder.decode(GuestAPI.Links.self, from: Data(json.utf8)))
        XCTAssertEqual(index[DiscussionStore.key(for: URL(string: "https://beta.iphoneblog.de/2026/11/15/kw-46/")!)], "$root46")
        XCTAssertNil(index[DiscussionStore.key(for: URL(string: "https://www.iphoneblog.de/2026/11/13/other/")!)])
    }

    func testEmptyLinksFileMeansNoDiscussion() throws {
        let links = try GuestAPI.decoder.decode(GuestAPI.Links.self, from: Data(#"{"generated_ts":1,"links":{}}"#.utf8))
        XCTAssertTrue(DiscussionStore.index(links).isEmpty)
    }
}

/// WordPress's web login for members (iphoneblog-wordpress PR #276).
final class WebLoginTests: XCTestCase {
    private let host = "beta.iphoneblog.de"

    func testOneTimeAddressIsOpened() {
        let body = #"{"url":"https://beta.iphoneblog.de/chat/web-login/?app=1&t=abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG","expires_in":60}"#
        XCTAssertEqual(WebLogin.outcome(status: 200, body: body, pageHost: host),
                       .open(URL(string: "https://beta.iphoneblog.de/chat/web-login/?app=1&t=abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG")!))
    }

    func testAnswerPointingElsewhereIsRefused() {
        let other = #"{"url":"https://evil.example/chat/web-login/?t=x","expires_in":60}"#
        let path = #"{"url":"https://beta.iphoneblog.de/wp-admin/","expires_in":60}"#
        let plain = #"{"url":"http://beta.iphoneblog.de/chat/web-login/?t=x","expires_in":60}"#
        for body in [other, path, plain] {
            guard case .stop = WebLogin.outcome(status: 200, body: body, pageHost: host) else {
                return XCTFail("opened \(body)")
            }
        }
    }

    func testRefusedTokenAsksForAFreshOne() {
        XCTAssertEqual(WebLogin.outcome(status: 401, body: #"{"code":"web_login_token","message":"x"}"#, pageHost: host),
                       .refreshToken)
    }

    func testOtherErrorsStopWithTheirCode() {
        XCTAssertEqual(WebLogin.outcome(status: 503, body: #"{"code":"web_login_off","message":"x"}"#, pageHost: host),
                       .stop("503 web_login_off"))
        XCTAssertEqual(WebLogin.outcome(status: 404, body: "<html>", pageHost: host), .stop("404 -"))
    }

    func testWeiterIsThePathWithoutHostOrFlag() {
        XCTAssertEqual(WebLogin.weiter(for: URL(string: "https://beta.iphoneblog.de/2026/11/15/kw-46/?app=1")!), "/2026/11/15/kw-46/")
        XCTAssertEqual(WebLogin.weiter(for: URL(string: "https://beta.iphoneblog.de")!), "/")
        XCTAssertEqual(WebLogin.weiter(for: nil), "/")
    }

    func testOnlyWordPressCookiesGo() {
        let make = { (name: String) in HTTPCookie(properties: [.name: name, .value: "1", .domain: "beta.iphoneblog.de", .path: "/"])! }
        XCTAssertTrue(WordPressCookies.isWordPress(make("wordpress_logged_in_abc")))
        XCTAssertFalse(WordPressCookies.isWordPress(make("_oauth2_proxy")))
    }
}
