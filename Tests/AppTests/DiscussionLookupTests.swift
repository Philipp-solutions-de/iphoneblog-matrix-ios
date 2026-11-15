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
