@testable import iphoneblog
import SwiftUI
import XCTest

/// Für dich showed a preview's mentions as plain grey text (Philip, #bugs, build 195). Every
/// mention is marked as in the room timeline: mine white on solid teal, others teal on soft teal.
final class MentionHighlightTests: XCTestCase {
    private let html = #"<a href="https://matrix.to/#/@philip:iphoneblog.de">Philip Braeunlich</a> <a href="https://matrix.to/#/@kyrios:iphoneblog.de">@Kyrios</a> Ein GIF, das du aus Gboard einfügst"#
    private let body = "Philip Braeunlich Kyrios Ein GIF, das du aus Gboard einfügst"

    func testNamesFromHTMLAndMarkdown() {
        XCTAssertEqual(PushText.mentions(body: body, formattedBody: html), ["@Philip Braeunlich", "@Kyrios"])
        let markdown = "[Philip Braeunlich](https://matrix.to/#/@philip:iphoneblog.de) und [@Kyrios](https://matrix.to/#/@kyrios:iphoneblog.de) da"
        XCTAssertEqual(PushText.mentions(body: markdown), ["@Philip Braeunlich", "@Kyrios"])
        XCTAssertEqual(PushText.mentions(body: "kein Name hier"), [])
    }

    /// Philip's preview: both mentions marked, his own one as "me".
    func testFuerDichPreviewMarksEveryMention() {
        let plain = PushText.plain(body: body, formattedBody: html)
        let names = PushText.mentions(body: body, formattedBody: html)
        let text = MentionRow.highlight(plain, mentioned: names, me: ["Philip Braeunlich", "philip"])

        let philip = try! XCTUnwrap(text.range(of: "@Philip Braeunlich"))
        XCTAssertEqual(text[philip].foregroundColor, .white)
        XCTAssertEqual(text[philip].backgroundColor, Theme.badge)

        let kyrios = try! XCTUnwrap(text.range(of: "@Kyrios"))
        XCTAssertEqual(text[kyrios].foregroundColor, Theme.teal)
        XCTAssertEqual(text[kyrios].backgroundColor, Theme.tealSoft)

        let rest = try! XCTUnwrap(text.range(of: "Ein GIF"))
        XCTAssertNil(text[rest].foregroundColor, "only the mentions are marked")
    }

    /// A client that typed "@Name" without a link: my own name is still marked.
    func testPlainTextMentionOfMeStillMarked() {
        let text = MentionRow.highlight("@Philip schau mal", mentioned: [], me: ["Philip"])
        let range = try! XCTUnwrap(text.range(of: "@Philip"))
        XCTAssertEqual(text[range].backgroundColor, Theme.badge)
    }
}
