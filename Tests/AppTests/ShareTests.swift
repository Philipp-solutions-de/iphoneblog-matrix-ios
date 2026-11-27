@testable import iphoneblog
import XCTest

/// The share extension's events and its room list (ShareMessage, ShareTargets).
final class ShareTests: XCTestCase {
    private let link = URL(string: "https://www.iphoneblog.de/2026/11/27/artikel/")!

    func testTextIsWordsThenLink() {
        XCTAssertEqual(ShareMessage.text(words: "  Lest das  \n", link: link), "Lest das\n\nhttps://www.iphoneblog.de/2026/11/27/artikel/")
        XCTAssertEqual(ShareMessage.text(words: "", link: link), link.absoluteString)
        XCTAssertEqual(ShareMessage.text(words: "Nur Text", link: nil), "Nur Text")
        XCTAssertNil(ShareMessage.text(words: " \n ", link: nil))
    }

    func testLinkNotRepeatedWhenTheWordsHoldIt() {
        XCTAssertEqual(ShareMessage.text(words: "Hier: \(link.absoluteString) schaut mal", link: link),
                       "Hier: \(link.absoluteString) schaut mal")
    }

    func testTextContentIsPlainMText() throws {
        let content = try object(ShareMessage.textContent("Hallo\n\nhttps://x.de/a"))
        XCTAssertEqual(content["msgtype"] as? String, "m.text")
        XCTAssertEqual(content["body"] as? String, "Hallo\n\nhttps://x.de/a")
        XCTAssertNil(content["format"])
    }

    func testImageWithCaptionKeepsTheFileName() throws {
        let image = ShareMessage.Image(url: "mxc://iphoneblog.de/abc", mimeType: "image/jpeg", fileName: "Bild.jpg",
                                       size: 1234, width: 2560, height: 1920)
        let captioned = try object(ShareMessage.imageContent(image, caption: " Schau "))
        XCTAssertEqual(captioned["msgtype"] as? String, "m.image")
        XCTAssertEqual(captioned["url"] as? String, "mxc://iphoneblog.de/abc")
        XCTAssertEqual(captioned["body"] as? String, "Schau")
        XCTAssertEqual(captioned["filename"] as? String, "Bild.jpg")
        let info = try XCTUnwrap(captioned["info"] as? [String: Any])
        XCTAssertEqual(info["mimetype"] as? String, "image/jpeg")
        XCTAssertEqual(info["size"] as? Int, 1234)
        XCTAssertEqual(info["w"] as? Int, 2560)
        XCTAssertEqual(info["h"] as? Int, 1920)

        let bare = try object(ShareMessage.imageContent(image, caption: nil))
        XCTAssertEqual(bare["body"] as? String, "Bild.jpg")
        XCTAssertNil(bare["filename"])
    }

    func testOnlyWebLinksAreLinks() {
        XCTAssertEqual(ShareMessage.webLink(link), link)
        XCTAssertNil(ShareMessage.webLink(URL(string: "file:///private/var/mobile/a.txt")))
        XCTAssertNil(ShareMessage.webLink(URL(string: "mailto:a@b.de")))
        XCTAssertEqual(ShareMessage.link(inText: " https://x.de/a \n"), URL(string: "https://x.de/a"))
        XCTAssertNil(ShareMessage.link(inText: "Schau https://x.de/a"))
        XCTAssertNil(ShareMessage.link(inText: "Hallo"))
    }

    func testRoomsAreJoinedAndUnlockedInOrder() {
        let rooms = ShareTargets.rooms(from: [("!a", "#one-Chat", false), ("!b", "Locked", true),
                                              ("!c", "Nicht drin", false), ("!d", "Apps", false)],
                                       joined: ["!a", "!b", "!d"])
        XCTAssertEqual(rooms.map(\.id), ["!a", "!d"])
        XCTAssertEqual(ShareTargets.rooms(from: [("!a", "#one-Chat", false)], joined: []), [])
    }

    func testPreselectsTheLastRoomWhileOffered() {
        let targets = ShareTargets(userID: "@a:x", rooms: [.init(id: "!a", name: "A"), .init(id: "!b", name: "B")])
        XCTAssertEqual(targets.preselected(last: "!b")?.id, "!b")
        XCTAssertEqual(targets.preselected(last: "!gone")?.id, "!a")
        XCTAssertEqual(targets.preselected(last: nil)?.id, "!a")
        XCTAssertNil(ShareTargets(userID: "@a:x", rooms: []).preselected(last: "!a"))
    }

    func testStoredListBelongsToItsAccount() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ShareTests"))
        defer { defaults.removePersistentDomain(forName: "ShareTests") }
        ShareTargets(userID: "@a:x", rooms: [.init(id: "!a", name: "A")]).save(to: defaults)
        ShareTargets.remember(roomID: "!a", in: defaults)
        XCTAssertEqual(ShareTargets.load(for: "@a:x", from: defaults)?.rooms.map(\.id), ["!a"])
        XCTAssertNil(ShareTargets.load(for: "@b:x", from: defaults))
        XCTAssertEqual(ShareTargets.lastRoomID(in: defaults), "!a")
        ShareTargets.forget(in: defaults)
        XCTAssertNil(ShareTargets.load(for: "@a:x", from: defaults))
        XCTAssertNil(ShareTargets.lastRoomID(in: defaults))
    }

    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}
