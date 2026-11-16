@testable import iphoneblog
import XCTest

final class ReplyTextTests: XCTestCase {
    private func links(_ text: AttributedString) -> [String] {
        text.runs.compactMap { $0.link?.absoluteString }
    }

    func testBareAddressBecomesALink() {
        let text = ReplyText.attributed("Lies das: https://www.iphoneblog.de/ und www.apple.com")
        XCTAssertEqual(links(text), ["https://www.iphoneblog.de/", "http://www.apple.com"])
        XCTAssertEqual(String(text.characters), "Lies das: https://www.iphoneblog.de/ und www.apple.com")
    }

    func testMarkdownShowsWithoutItsMarks() {
        let text = ReplyText.attributed("**Fett**, *kursiv* und `Code` mit [Link](https://example.org)")
        XCTAssertEqual(String(text.characters), "Fett, kursiv und Code mit Link")
        XCTAssertEqual(links(text), ["https://example.org"])
        let bold = text.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertEqual(bold.map { String(text[$0.range].characters) }, "Fett")
    }

    func testReplyFallbackIsDropped() {
        let body = "> <@writer:localhost> Fett, kursiv\n> zweite Zeile\n\nDie Antwort zitiert."
        XCTAssertEqual(String(ReplyText.attributed(body).characters), "Die Antwort zitiert.")
    }

    func testLineBreaksStay() {
        XCTAssertEqual(String(ReplyText.attributed("eins\nzwei").characters), "eins\nzwei")
    }
}

final class ReplyHTMLTests: XCTestCase {
    /// The live reply in the Screens thread, as the server sends it.
    private let screens = #"<p>Meine Einstellungen für unterwegs:</p><ul><li><strong>Hochleistung</strong> nur im WLAN</li><li><strong>Dynamische Auflösung</strong> immer an</li><li>Ton vom Mac <em>aus</em></li></ul><p>Details: <a href="https://blog.edovia.com/" target="_blank" rel="noopener noreferrer">https://blog.edovia.com/</a></p>"#

    func testParagraphsListAndLink() {
        let text = ReplyHTML.attributed(screens)
        XCTAssertEqual(String(text.characters), """
        Meine Einstellungen für unterwegs:

        • Hochleistung nur im WLAN
        • Dynamische Auflösung immer an
        • Ton vom Mac aus

        Details: https://blog.edovia.com/
        """)
        XCTAssertEqual(text.runs.compactMap { $0.link?.absoluteString }, ["https://blog.edovia.com/"])
        let bold = text.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertEqual(bold.map { String(text[$0.range].characters) }, ["Hochleistung", "Dynamische Auflösung"])
        let italic = text.runs.filter { $0.inlinePresentationIntent?.contains(.emphasized) == true }
        XCTAssertEqual(italic.map { String(text[$0.range].characters) }, ["aus"])
    }

    func testEntitiesBreaksPillsAndUnsafeLinks() {
        let text = ReplyHTML.attributed(#"<span class="pill">@Lena K.</span> Tom &amp; Jerry&nbsp;&lt;3<br>zweite &#x1F600; <a href="javascript:alert(1)">weg</a>"#)
        XCTAssertEqual(String(text.characters), "@Lena K. Tom & Jerry\u{00A0}<3\nzweite 😀 weg")
        XCTAssertTrue(text.runs.allSatisfy { $0.link == nil }, "javascript: must not become a link")
        let pill = text.runs.first { $0.backgroundColor != nil }
        XCTAssertEqual(pill.map { String(text[$0.range].characters) }, "@Lena K.")
    }

    func testOrderedListQuoteAndCode() {
        let text = ReplyHTML.attributed("<ol><li>eins</li><li>zwei</li></ol><blockquote><p>Zitat</p></blockquote><p><code>let x = 1</code></p>")
        XCTAssertEqual(String(text.characters), "1. eins\n2. zwei\n\n▎Zitat\n\nlet x = 1")
    }

    func testPlainBodyWhenNoHTML() {
        XCTAssertEqual(String(ReplyText.attributed(body: "**fett**", formattedBody: nil).characters), "fett")
        XCTAssertEqual(String(ReplyText.attributed(body: "x", formattedBody: "<p>y</p>").characters), "y")
    }
}

final class GuestReplyDecodingTests: XCTestCase {
    /// The server's shape (2026-11-14_interfaces.md): a picture reply and a formatted one.
    func testPictureAndFormattedReplies() throws {
        let json = Data(#"""
        {"root": {"root_event_id": "$r", "title": "Screens", "link": null, "image_url": null, "teaser": null,
                  "published_ts": 1, "reply_count": 2, "latest_reply_ts": 2, "last_repliers": []},
         "replies": [
          {"event_id": "$a", "ts": 1, "sender_name": "Tobias M.", "msgtype": "m.image", "body": "📷 Bild",
           "media": {"id": "abc", "url": "https://chat.iphoneblog.de/_iphoneblog/v1/blog/media/abc.jpg",
                     "mimetype": "image/jpeg", "w": 800, "h": 600, "size": 1234,
                     "thumbnail_url": "https://chat.iphoneblog.de/_iphoneblog/v1/blog/media/abc-t.jpg",
                     "thumbnail_w": 320, "thumbnail_h": 240}},
          {"event_id": "$b", "ts": 2, "sender_name": "Markus R.", "msgtype": "m.text", "body": "**x**",
           "formatted_body": "<strong>x</strong>"}],
         "next": null}
        """#.utf8)
        let page = try GuestAPI.decoder.decode(GuestAPI.ThreadPage.self, from: json)
        XCTAssertEqual(page.replies[0].media?.thumbnailUrl?.lastPathComponent, "abc-t.jpg")
        XCTAssertEqual(page.replies[0].media?.thumbnailW, 320)
        XCTAssertNil(page.replies[1].media)
        XCTAssertEqual(page.replies[1].formattedBody, "<strong>x</strong>")
    }
}
