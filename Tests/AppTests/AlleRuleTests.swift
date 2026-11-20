import XCTest
@testable import iphoneblog

/// Reading a #one room's push mode from the account's rules (alle-notify-rule.md, "Reading").
final class AlleRuleTests: XCTestCase {
    private let room = "!raum:iphoneblog.de"

    private func modes(_ rules: [String: Any]) -> (NotificationPrefs.ChannelMode?, [String]) {
        let read = NotificationPrefs.modes(rules: rules, rooms: [room])
        return (read.modes[room], read.legacy)
    }

    func testNoRuleIsMentionsOnly() {
        XCTAssertEqual(modes([:]).0, .mentions)
    }

    func testUnderrideIsAlle() {
        let (mode, legacy) = modes(["underride": [["rule_id": "de.iphoneblog.alle.\(room)", "enabled": true, "actions": ["notify"]]]])
        XCTAssertEqual(mode, .all)
        XCTAssertEqual(legacy, [])
    }

    func testOldRoomRuleIsAlleAndMoves() {
        let (mode, legacy) = modes(["room": [["rule_id": room, "enabled": true, "actions": ["notify"]]]])
        XCTAssertEqual(mode, .all)
        XCTAssertEqual(legacy, [room])
    }

    func testQuietRoomRuleStaysAlone() {
        let (mode, legacy) = modes(["room": [["rule_id": room, "enabled": true, "actions": ["dont_notify"]]]])
        XCTAssertEqual(mode, .mentions)
        XCTAssertEqual(legacy, [])
    }

    func testOverrideWithoutNotifyIsAus() {
        let (mode, legacy) = modes(["override": [["rule_id": room, "enabled": true, "actions": []]],
                                    "room": [["rule_id": room, "enabled": true, "actions": ["notify"]]]])
        XCTAssertEqual(mode, .mute)
        XCTAssertEqual(legacy, [], "a muted room keeps its old rule until someone picks Alle")
    }

    func testDisabledRulesCountForNothing() {
        XCTAssertEqual(modes(["underride": [["rule_id": "de.iphoneblog.alle.\(room)", "enabled": false, "actions": ["notify"]]]]).0, .mentions)
    }

    func testRulePathEncodesTheRoomID() {
        XCTAssertEqual(NotificationPrefs.rulePath("underride", "de.iphoneblog.alle.!a:b.de"),
                       "/_matrix/client/v3/pushrules/global/underride/de.iphoneblog.alle.%21a%3Ab.de")
    }
}
