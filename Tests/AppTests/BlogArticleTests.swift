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

    func testGuestAPIDecodes() throws {
        let json = #"{"threads":[{"root_event_id":"$r","ts":1763200000000,"title":"T","image_url":"https://x/i.jpg","link":"https://x/a","reply_count":2,"latest_reply_ts":1763200100000}],"next":null}"#
        let page = try GuestAPI.decoder.decode(GuestAPI.ThreadsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.threads.first?.article.replyCount, 2)
        XCTAssertEqual(page.threads.first?.article.imageURL?.lastPathComponent, "i.jpg")
    }
}
