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

        await model.signOut()
        store.delete()
    }
}
