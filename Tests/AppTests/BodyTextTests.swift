import ChatKit
import XCTest

/// Lines after a break start at the text's edge (Philip, 2026-11-20, build 220: "Der Text ist
/// wieder nicht aligned"). The event as the server holds it: the body has a space before each
/// newline, the formatted body "<br />" and a newline.
@MainActor
final class BodyTextTests: XCTestCase {
    func testLinesAfterABreakAreNotIndented() throws {
        let shown = try XCTUnwrap(ChatBodyText.shown(html: "Ja genau.<br />\nBuild 220.<br />\nIm thread nicht."))
        XCTAssertEqual(shown, "Ja genau.\nBuild 220.\nIm thread nicht.")
    }

    func testAnIntendedSpaceInsideALineStays() throws {
        let shown = try XCTUnwrap(ChatBodyText.shown(html: "eins<br />zwei drei"))
        XCTAssertEqual(shown, "eins\nzwei drei")
    }
}
