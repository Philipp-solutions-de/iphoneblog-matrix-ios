import XCTest
@testable import iphoneblog

/// Where links in the blog's web view lead, and how a discussion is found.
final class BlogLinksTests: XCTestCase {
    private let beta = "beta.iphoneblog.de"

    func testDiscussionLinkOpensTheArticle() {
        let link = URL(string: "iphoneblog-chat://diskussion?url=https%3A%2F%2Fwww.iphoneblog.de%2F2026%2F11%2F14%2Fkw46%2F")!
        XCTAssertEqual(BlogLinks.classify(link, blogHost: beta),
                       .discussion(URL(string: "https://www.iphoneblog.de/2026/11/14/kw46/")!))
    }

    func testDiscussionLinkWithoutURLIsIgnored() {
        XCTAssertEqual(BlogLinks.classify(URL(string: "iphoneblog-chat://diskussion")!, blogHost: beta), .ignore)
    }

    func testBlogPageKeepsAppView() {
        let page = URL(string: "https://beta.iphoneblog.de/2026/11/14/kw46/")!
        XCTAssertEqual(BlogLinks.classify(page, blogHost: beta),
                       .blog(keepingAppView: URL(string: "https://beta.iphoneblog.de/2026/11/14/kw46/?app=1")!))
        let already = URL(string: "https://beta.iphoneblog.de/page/2/?app=1")!
        XCTAssertEqual(BlogLinks.classify(already, blogHost: beta), .blog(keepingAppView: nil))
    }

    func testOtherSitesOpenInSafari() {
        XCTAssertEqual(BlogLinks.classify(URL(string: "https://www.apple.com/de/")!, blogHost: beta), .external)
        XCTAssertEqual(BlogLinks.classify(URL(string: "mailto:a@example.org")!, blogHost: beta), .external)
        XCTAssertEqual(BlogLinks.classify(URL(string: "about:blank")!, blogHost: beta), .ignore)
    }

    func testTestHostCountsAsBlog() {
        let local = URL(string: "http://127.0.0.1:8791/blog/")!
        XCTAssertEqual(BlogLinks.classify(local, blogHost: "127.0.0.1"),
                       .blog(keepingAppView: URL(string: "http://127.0.0.1:8791/blog/?app=1")!))
    }

    func testDiscussionKeyIsThePath() {
        // links.json keys carry www; the app view links may carry beta. Only the path counts.
        let live = URL(string: "https://www.iphoneblog.de/2026/11/14/kw46/")!
        let beta = URL(string: "https://beta.iphoneblog.de/2026/11/14/kw46")!
        XCTAssertEqual(DiscussionStore.key(for: live), DiscussionStore.key(for: beta))
        XCTAssertEqual(DiscussionStore.key(for: live), "/2026/11/14/kw46/")
    }

    func testLocalpart() {
        XCTAssertEqual(MentionsModel.localpart("@tim:iphoneblog.de"), "tim")
    }

    func testReplyTimes() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(ReplyRow.format(yesterday, now: now).hasPrefix("Gestern, "))
        XCTAssertEqual(MentionRow.shortTime(yesterday, now: now), "Gestern")
    }

    func testArticleThreadEndpointSitsBesideTheBlogFiles() {
        let base = URL(string: "https://chat.iphoneblog.de/_iphoneblog/v1/blog")!
        XCTAssertEqual(DiscussionStore.articleThreadURL(base: base).absoluteString,
                       "https://chat.iphoneblog.de/_iphoneblog/v1/article-thread")
    }

    func testArticleThreadGetsTheArticlesOwnAddress() {
        // The web view may be on beta with app=1; the server wants www without a query.
        let beta = URL(string: "https://beta.iphoneblog.de/2023/02/28/tipp-in-der-reader-darstellung/?app=1#c")!
        XCTAssertEqual(DiscussionStore.canonical(beta).absoluteString,
                       "https://www.iphoneblog.de/2023/02/28/tipp-in-der-reader-darstellung/")
    }
}
