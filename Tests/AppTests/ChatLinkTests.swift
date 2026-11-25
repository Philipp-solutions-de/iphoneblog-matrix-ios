import XCTest
@testable import iphoneblog

/// The readable chat links (ChatLink): what "Link kopieren" copies and what the app opens. The
/// form is shared with the web chat; change it only together with it.
final class ChatLinkTests: XCTestCase {
    func testMessageUsesTheAlias() {
        let url = ChatLink.url(roomID: "!abc", alias: "#allgemein:iphoneblog.de", eventID: "$Ev3nt_x-Y")
        XCTAssertEqual(url?.absoluteString, "https://chat.iphoneblog.de/#/allgemein/$Ev3nt_x-Y")
    }

    func testRoomWithoutAliasUsesItsEncodedID() {
        XCTAssertEqual(ChatLink.url(roomID: "!abc:iphoneblog.de", alias: nil, eventID: "$e")?.absoluteString,
                       "https://chat.iphoneblog.de/#/%21abc%3Aiphoneblog.de/$e")
        // Room v12: no server part.
        XCTAssertEqual(ChatLink.url(roomID: "!abcDEF_12", alias: nil, eventID: nil)?.absoluteString,
                       "https://chat.iphoneblog.de/#/%21abcDEF_12")
    }

    func testOtherServersAliasIsNotShortened() {
        XCTAssertEqual(ChatLink.url(roomID: "!abc", alias: "#x:matrix.org", eventID: nil)?.absoluteString,
                       "https://chat.iphoneblog.de/#/%21abc")
    }

    func testParsesWhatItBuilds() {
        let cases: [(String, String?, String?, String)] = [
            ("!abc", nil, nil, "!abc"), ("!abc", nil, "$e", "!abc"), ("!abc:iphoneblog.de", nil, "$e", "!abc:iphoneblog.de"),
            ("!abc", "#blog:iphoneblog.de", "$e", "#blog:iphoneblog.de"), ("!abc", "#one-chat:iphoneblog.de", nil, "#one-chat:iphoneblog.de"),
        ]
        for (roomID, alias, event, room) in cases {
            let url = ChatLink.url(roomID: roomID, alias: alias, eventID: event)
            XCTAssertEqual(url.flatMap(ChatLink.parse), ChatLink(room: room, eventID: event), url?.absoluteString ?? "nil")
        }
    }

    func testReadsEncodedDollar() {
        XCTAssertEqual(ChatLink.parse(URL(string: "https://chat.iphoneblog.de/#/one-chat/%24ev")!),
                       ChatLink(room: "#one-chat:iphoneblog.de", eventID: "$ev"))
    }

    func testReadsMatrixToLinks() {
        XCTAssertEqual(ChatLink.parse(URL(string: "https://matrix.to/#/!abc:iphoneblog.de/$ev?via=iphoneblog.de")!),
                       ChatLink(room: "!abc:iphoneblog.de", eventID: "$ev"))
        XCTAssertEqual(ChatLink.parse(URL(string: "https://matrix.to/#/%23one-chat:iphoneblog.de")!),
                       ChatLink(room: "#one-chat:iphoneblog.de"))
    }

    func testLeavesOtherLinksAlone() {
        for string in ["https://matrix.to/#/@thorsten:iphoneblog.de", "https://www.iphoneblog.de/2026/11/17/x/",
                       "https://chat.iphoneblog.de/", "https://chat.iphoneblog.de/app/privacy",
                       "https://chat.iphoneblog.de/#/one-chat/whatever",
                       "https://chat.iphoneblog.de/#/one-chat/t/one-chat:%24abc!/blog:%24def"] {
            XCTAssertNil(ChatLink.parse(URL(string: string)!), string)
        }
    }

    /// Philip, #bugs 2026-11-21: a tap on a person's link opened matrix.to in the browser.
    func testUserLinkNamesThePerson() {
        XCTAssertEqual(ChatLink.userID(URL(string: "https://matrix.to/#/@dominic:iphoneblog.de")!), "@dominic:iphoneblog.de")
        XCTAssertEqual(ChatLink.userID(URL(string: "https://matrix.to/#/%40dominic%3Aiphoneblog.de")!), "@dominic:iphoneblog.de")
        XCTAssertEqual(ChatLink.userID(URL(string: "https://matrix.to/#/@phlp:iphoneblog.de?via=iphoneblog.de")!), "@phlp:iphoneblog.de")
        XCTAssertNil(ChatLink.userID(URL(string: "https://matrix.to/#/#allgemein:iphoneblog.de")!), "a room is no person")
        XCTAssertNil(ChatLink.userID(URL(string: "https://matrix.to/#/@nobody")!), "no server, no person")
        XCTAssertNil(ChatLink.userID(URL(string: "https://example.com/#/@dominic:iphoneblog.de")!), "another host")
        XCTAssertNil(ChatLink.parse(URL(string: "https://matrix.to/#/@dominic:iphoneblog.de")!), "and still no room link")
    }
}
