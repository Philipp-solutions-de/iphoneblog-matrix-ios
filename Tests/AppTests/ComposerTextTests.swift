import ChatKit
import XCTest

final class ComposerTextTests: XCTestCase {
    /// Thorsten's message (2026-11-16): the mention went out as a markdown link in `body`.
    func testMentionIsPlainInBodyAndALinkInHTML() {
        let typed = "Hey [Dominic](https://matrix.to/#/@dominic:iphoneblog.de) schau mal"
        XCTAssertTrue(ComposerText.hasMention(typed))
        XCTAssertEqual(ComposerText.plainBody(typed), "Hey Dominic schau mal")
        XCTAssertEqual(ComposerText.html(typed),
                       #"Hey <a href="https://matrix.to/#/@dominic:iphoneblog.de">Dominic</a> schau mal"#)
    }

    func testInlineMarkdownAndEscaping() {
        let typed = "**fett** & *schräg* `a<b` [Link](https://example.org)\nZeile 2"
        XCTAssertFalse(ComposerText.hasMention(typed))
        XCTAssertEqual(ComposerText.html(typed),
                       #"<strong>fett</strong> &amp; <em>schräg</em> <code>a&lt;b</code> <a href="https://example.org">Link</a><br>Zeile 2"#)
    }

    /// A mention picked from the list, then text (Alex's message, 2026-11-17): the composer's
    /// markdown, as Element X hands it over, becomes a plain body and a link in HTML.
    func testPickedMentionThenText() {
        let markdown = "[Kyrios](https://matrix.to/#/@kyrios:iphoneblog.de) Wir könnten das so machen"
        XCTAssertTrue(ComposerText.hasMention(markdown))
        XCTAssertEqual(ComposerText.plainBody(markdown), "Kyrios Wir könnten das so machen")
        XCTAssertEqual(ComposerText.html(markdown),
                       #"<a href="https://matrix.to/#/@kyrios:iphoneblog.de">Kyrios</a> Wir könnten das so machen"#)
    }
}
