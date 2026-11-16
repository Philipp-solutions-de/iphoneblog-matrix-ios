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
