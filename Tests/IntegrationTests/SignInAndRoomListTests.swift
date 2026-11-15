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
        }

        // Blog, signed in: the article's title and teaser come from the bot's field.
        if let title = env["IPHONEBLOG_TEST_ARTICLE_TITLE"], !title.isEmpty {
            let feed = try XCTUnwrap(session.blogFeed, "no Blog room")
            await feed.load()
            let until = Date().addingTimeInterval(30)
            while Date() < until, feed.articles.first?.teaser == nil { try await Task.sleep(for: .milliseconds(250)) }
            let article = try XCTUnwrap(feed.articles.first)
            XCTAssertEqual(article.title, title)
            XCTAssertEqual(article.teaser, "Zwei Zeilen Vorschau auf den Artikel.")
            XCTAssertEqual(article.replyCount, 1)
        }

        await model.signOut()
        store.delete()
    }
}
