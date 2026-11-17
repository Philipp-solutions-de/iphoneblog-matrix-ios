@testable import iphoneblog
import XCTest

final class PushTextTests: XCTestCase {
    /// Thorsten's lock screen: "##one-Chat" and the raw markdown mention without its space.
    func testTheMessageFromThorstensLockScreen() {
        XCTAssertEqual(PushText.title(room: "#one-Chat", inThread: false), "#one-Chat")
        let body = "Das gefällt dem [Philip Braeunlich](https://matrix.to/#/@phlp:iphoneblog.de)nicht"
        XCTAssertEqual(PushText.plain(body: body), "Das gefällt dem @Philip Braeunlich nicht")
    }

    func testFormattedBodyWinsAndMentionsReadAsNames() {
        let html = #"Das gefällt dem <a href="https://matrix.to/#/@phlp:iphoneblog.de">Philip Braeunlich</a> <strong>nicht</strong> &amp; mir auch nicht"#
        XCTAssertEqual(PushText.plain(body: "egal", formattedBody: html),
                       "Das gefällt dem @Philip Braeunlich nicht & mir auch nicht")
    }

    func testMarkdownMarksGo() {
        XCTAssertEqual(PushText.plain(body: "**Fett**, *kursiv*, `Code` und [ein Link](https://example.org)"),
                       "Fett, kursiv, Code und ein Link")
        XCTAssertEqual(PushText.plain(body: "> <@a:b> Zitat\n\nDie Antwort"), "Die Antwort")
        XCTAssertEqual(PushText.plain(body: "Datei_name_mit_unterstrichen bleibt"), "Datei_name_mit_unterstrichen bleibt")
    }

    func testTitles() {
        XCTAssertEqual(PushText.title(room: "Fotos", inThread: false), "#Fotos")
        XCTAssertEqual(PushText.title(room: "#one-Chat", inThread: true), "#one-Chat · Thread")
    }

    /// Alex's message in #bugs (2026-11-17), from the iOS build before #30: the pill as markdown
    /// in body, a correct formatted_body. Either way the preview reads "@Kyrios".
    func testAlexsMentionReadsAsAName() {
        let body = "[Kyrios](https://matrix.to/#/@kyrios:iphoneblog.de) Wir könnten das so machen"
        let html = #"<a href="https://matrix.to/#/@kyrios:iphoneblog.de">Kyrios</a> Wir könnten das so machen"#
        XCTAssertEqual(PushText.plain(body: body), "@Kyrios Wir könnten das so machen")
        XCTAssertEqual(PushText.plain(body: body, formattedBody: html), "@Kyrios Wir könnten das so machen")
    }
}
