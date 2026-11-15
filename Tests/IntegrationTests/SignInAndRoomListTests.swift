import XCTest
@testable import iphoneblog

/// Signs in against a real test homeserver and waits for its rooms.
/// scripts/test-homeserver.sh starts one and creates the user and rooms; the workflow
/// passes its address and the test account in TEST_RUNNER_* variables.
@MainActor
final class SignInAndRoomListTests: XCTestCase {
    func testPasswordSignInListsRooms() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPHONEBLOG_TEST_HOMESERVER"],
              let user = env["IPHONEBLOG_TEST_USER"],
              let password = env["IPHONEBLOG_TEST_PASSWORD"] else {
            throw XCTSkip("no test homeserver configured")
        }
        let expected = (env["IPHONEBLOG_TEST_ROOMS"] ?? "").split(separator: ",").map(String.init)

        let store = SessionStore(service: "integration-tests.\(UUID().uuidString)")
        let model = AppModel(homeserverURL: server, store: store)
        await model.signIn(username: user, password: password)

        guard case .signedIn(let session) = model.state else {
            return XCTFail("not signed in: \(model.errorMessage ?? "no message")")
        }
        XCTAssertTrue(session.userID.hasPrefix("@\(user):"), session.userID)

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let names = Set(session.rooms.rooms.map(\.name))
            if expected.allSatisfy(names.contains) { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let names = Set(session.rooms.rooms.map(\.name))
        for room in expected {
            XCTAssertTrue(names.contains(room), "room \(room) missing; have \(names.sorted())")
        }

        // The second user's mention shows as an unread mention on that room.
        if let mentionRoom = env["IPHONEBLOG_TEST_MENTION_ROOM"], !mentionRoom.isEmpty {
            let until = Date().addingTimeInterval(30)
            while Date() < until, session.rooms.rooms.first(where: { $0.name == mentionRoom })?.unreadMentions ?? 0 == 0 {
                try await Task.sleep(for: .milliseconds(250))
            }
            let room = try XCTUnwrap(session.rooms.rooms.first { $0.name == mentionRoom })
            XCTAssertGreaterThanOrEqual(room.unreadMentions, 1, "mention not counted")
            XCTAssertGreaterThanOrEqual(room.unreadMessages, 1, "messages not counted")
            XCTAssertEqual(session.rooms.withMentions.map(\.name), [mentionRoom])
        }

        // #one: the space makes the tester a member; its child Allgemein is the one channel.
        if env["IPHONEBLOG_ONE_ALIAS"] != nil {
            let until = Date().addingTimeInterval(30)
            while Date() < until, !session.isOneMember { try await Task.sleep(for: .milliseconds(250)) }
            XCTAssertTrue(session.isOneMember, "not a #one member")
            XCTAssertEqual(session.rooms.channels.map(\.name), ["Allgemein"])
            let channel = try XCTUnwrap(session.oneChannelID, "no #one-Chat channel")
            XCTAssertEqual(session.rooms.rooms.first { $0.id == channel }?.name, "Allgemein")
        }

        // The mention also reaches @Mentions, from the server's notification list.
        if let mentionRoom = env["IPHONEBLOG_TEST_MENTION_ROOM"], !mentionRoom.isEmpty {
            let until = Date().addingTimeInterval(30)
            while Date() < until, session.mentions.items.isEmpty {
                session.mentions.reload()
                try await Task.sleep(for: .seconds(1))
            }
            let mention = try XCTUnwrap(session.mentions.items.first, "no mention in @Mentions")
            XCTAssertTrue(mention.unread)
            XCTAssertGreaterThanOrEqual(session.mentions.unreadCount, 1)
        }

        // The Blog room is joined, and the new-articles push rule exists on the server.
        if env["IPHONEBLOG_BLOG_ALIAS"] != nil {
            XCTAssertNotNil(session.blogRoomID, "Blog room not resolved")
            let until = Date().addingTimeInterval(30)
            while Date() < until, !session.notificationPrefs.hasLoaded { try await Task.sleep(for: .milliseconds(250)) }
            await session.notificationPrefs.load()
            XCTAssertTrue(session.notificationPrefs.newArticles, "article push rule missing")
            session.notificationPrefs.setNewArticles(false)
            try await Task.sleep(for: .seconds(2))
            await session.notificationPrefs.load()
            XCTAssertFalse(session.notificationPrefs.newArticles, "article push rule not removed")
            session.notificationPrefs.setNewArticles(true)
            try await Task.sleep(for: .seconds(2))
        }

        await model.signOut()
        store.delete()
    }
}
