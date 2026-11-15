import XCTest
@testable import iphoneblog

final class BlogArticleTests: XCTestCase {
    func testTitleAndLinkFromBotPost() {
        let a = BlogArticle.parse(body: "iOS 27.2: Was sich beim Akku wirklich ändert\nhttps://www.iphoneblog.de/2026/11/15/akku/",
                                  eventID: "$1", date: .now, replies: 3, latest: nil)
        XCTAssertEqual(a.title, "iOS 27.2: Was sich beim Akku wirklich ändert")
        XCTAssertEqual(a.link?.host(), "www.iphoneblog.de")
        XCTAssertEqual(a.replyCount, 3)
    }

    func testTitleAndLinkOnOneLine() {
        let a = BlogArticle.parse(body: "Neu: Parcel im Test https://www.iphoneblog.de/parcel/", eventID: "$2", date: .now, replies: 0, latest: nil)
        XCTAssertEqual(a.title, "Neu: Parcel im Test")
        XCTAssertEqual(a.link?.path(), "/parcel/")
    }

    /// threads.json as agreed with the server session (2026-11-14_interfaces.md).
    func testThreadsJSONDecodes() throws {
        let json = #"{"generated_ts":1763200200000,"threads":[{"root_event_id":"$r","title":"T","link":"https://x/a","image_url":"https://x/i.jpg","teaser":"Kurz","published_ts":1763200000000,"reply_count":2,"latest_reply_ts":1763200100000,"last_repliers":[{"name":"Jana"}]}],"next":null}"#
        let page = try GuestAPI.decoder.decode(GuestAPI.ThreadsPage.self, from: Data(json.utf8))
        let article = try XCTUnwrap(page.threads.first?.article)
        XCTAssertEqual(article.replyCount, 2)
        XCTAssertEqual(article.teaser, "Kurz")
        XCTAssertEqual(article.repliers.map(\.name), ["Jana"])
        XCTAssertEqual(article.imageURL?.lastPathComponent, "i.jpg")
    }

    func testThreadFileDecodes() throws {
        let json = #"{"root":{"root_event_id":"$r","title":"T","link":null,"image_url":null,"teaser":null,"published_ts":1,"reply_count":1,"latest_reply_ts":2,"last_repliers":[]},"replies":[{"event_id":"$a","ts":2,"sender_name":"Jana","body":"Ja"}],"next":null}"#
        let page = try GuestAPI.decoder.decode(GuestAPI.ThreadPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.replies.first?.reply.sender, "Jana")
    }

    /// The bot's field on the root event, as the signed-in app reads it.
    @MainActor
    func testArticleFieldFromEventJSON() throws {
        let json = #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"T\\nhttps://x/a","de.iphoneblog.article":{"title":"Titel","link":"https://x/a","teaser":"Kurz","image_url":"https://x/i.jpg","published_ts":5}}}"#
        let field = try XCTUnwrap(MatrixBlogFeed.articleField(fromEventJSON: json))
        var article = BlogArticle.parse(body: "T", eventID: "$r", date: .distantPast, replies: 0, latest: nil)
        MatrixBlogFeed.merge(field, into: &article)
        XCTAssertEqual(article.title, "Titel")
        XCTAssertEqual(article.teaser, "Kurz")
        XCTAssertEqual(article.imageURL?.host(), "x")
        XCTAssertEqual(article.date, Date(milliseconds: 5))
    }
}
