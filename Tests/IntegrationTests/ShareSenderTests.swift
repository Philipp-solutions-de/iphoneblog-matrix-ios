import UIKit
import XCTest
@testable import iphoneblog

/// The share sheet's way out (ShareSender) against the test homeserver, beside a signed-in app
/// as on a phone: the app writes the #one rooms for the sheet, and a second client on the same
/// store (process "share-extension") posts a link and a captioned picture into one of them.
@MainActor
final class ShareSenderTests: XCTestCase {
    func testShareGoesIntoTheChosenOneRoom() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"], let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"], env["IPHONEBLOG_ONE_ALIAS"] != nil else {
            throw XCTSkip("no test homeserver configured")
        }
        let store = SessionStore(service: "share-tests.\(UUID().uuidString)")
        defer { store.delete() }
        let model = AppModel(homeserverURL: server, store: store)
        await model.signIn(username: user, password: password)
        guard case .signedIn(let session) = model.state else {
            return XCTFail("not signed in: \(model.errorMessage ?? "no message")")
        }

        // The app offers the #one rooms it writes in, by name.
        var targets: ShareTargets?
        let until = Date().addingTimeInterval(60)
        while Date() < until {
            targets = ShareTargets.load(for: session.userID)
            if targets?.rooms.count == 2 { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTAssertEqual(Set(targets?.rooms.map(\.name) ?? []), ["Allgemein", "Raum 2"], "the share sheet's rooms")
        let room = try XCTUnwrap(targets?.rooms.first { $0.name == "Raum 2" })

        let marker = "geteilt\(Int.random(in: 1000...9999))"
        let link = URL(string: "https://www.iphoneblog.de/\(marker)/")
        let sender = ShareSender(store: store)
        let text = try XCTUnwrap(ShareMessage.text(words: "Lest das \(marker)", link: link))
        let textEvents = try await sender.send(roomID: room.id, text: text, pictures: [])
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).pngData { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let pictureEvents = try await sender.send(roomID: room.id, text: "Bild \(marker)",
                                                  pictures: [.init(data: png, mimeType: "image/png", fileName: "Bild.png", width: 40, height: 30)])
        XCTAssertEqual(textEvents.count, 1)
        XCTAssertEqual(pictureEvents.count, 1)

        // Both are in the room as plain events any client reads.
        let encoded = try XCTUnwrap(room.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let data = try await session.api("GET", "/_matrix/client/v3/rooms/\(encoded)/messages?dir=b&limit=10")
        let chunk = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["chunk"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: chunk.compactMap { event in (event["event_id"] as? String).map { ($0, event) } })
        let textContent = try XCTUnwrap(byID[textEvents[0]]?["content"] as? [String: Any], "the text is not in the room")
        XCTAssertEqual(textContent["msgtype"] as? String, "m.text")
        XCTAssertEqual(textContent["body"] as? String, "Lest das \(marker)\n\nhttps://www.iphoneblog.de/\(marker)/")
        let imageContent = try XCTUnwrap(byID[pictureEvents[0]]?["content"] as? [String: Any], "the picture is not in the room")
        XCTAssertEqual(imageContent["msgtype"] as? String, "m.image")
        XCTAssertEqual(imageContent["body"] as? String, "Bild \(marker)")
        XCTAssertEqual(imageContent["filename"] as? String, "Bild.png")
        XCTAssertTrue((imageContent["url"] as? String)?.hasPrefix("mxc://") == true)

        // Signed out, the sheet offers no rooms.
        await model.signOut()
        XCTAssertNil(ShareTargets.load(for: session.userID))
    }
}
