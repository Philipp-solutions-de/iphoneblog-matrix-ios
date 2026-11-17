import XCTest
@testable import iphoneblog

/// A token error ends the session only on a definite answer (AuthGuard). Alex's logouts came
/// on deploy days: the SDK's refresh hit a restarting MAS and reported "unknown token".
@MainActor
final class AuthGuardTests: XCTestCase {
    private let hard401 = Data(#"{"errcode":"M_UNKNOWN_TOKEN","error":"Token is not active","soft_logout":false}"#.utf8)
    private let soft401 = Data(#"{"errcode":"M_UNKNOWN_TOKEN","soft_logout":true}"#.utf8)
    private let refresh502 = #"Generic(msg: "RefreshToken(Request(Status(502 Bad Gateway)))")"#

    /// One scripted answer per check; the last one repeats.
    private final class Script {
        var sdk: [String?]
        var whoami: [(Int, Data)?]
        var issuer: [Bool]
        var sleeps: [Duration] = []
        var signedOut = false
        var reasons: [String] = []
        var reports: [[String: String]] = []
        init(sdk: [String?], whoami: [(Int, Data)?] = [nil], issuer: [Bool] = [true]) {
            self.sdk = sdk; self.whoami = whoami; self.issuer = issuer
        }
        func next<T>(_ list: inout [T]) -> T { list.count > 1 ? list.removeFirst() : list[0] }
    }

    private func guardFor(_ script: Script) -> AuthGuard {
        AuthGuard(probes: .init(sdkRequest: { script.next(&script.sdk) },
                                whoami: { script.next(&script.whoami).map { (status: $0.0, body: $0.1) } },
                                issuerUp: { script.next(&script.issuer) },
                                sleep: { script.sleeps.append($0) }),
                  report: { script.reports.append($0) },
                  signOut: { script.signedOut = true; script.reasons.append($0) })
    }

    func testA502DuringRefreshKeepsTheSessionAndRetries() async {
        // MAS restarting: the refresh fails with 502, the old token is refused, MAS is down;
        // three checks later MAS is back and the refresh works.
        let script = Script(sdk: [refresh502, refresh502, refresh502, nil],
                            whoami: [(401, hard401)], issuer: [false, false, false, true])
        await guardFor(script).run()
        XCTAssertFalse(script.signedOut, "a 502 during refresh signed out")
        XCTAssertEqual(script.sleeps, [.seconds(2), .seconds(4), .seconds(8)])
    }

    func testTimeoutsAndResetsKeepTheSession() async {
        let script = Script(sdk: ["URLError(-1001 timed out)", "connection reset by peer", nil], whoami: [nil])
        await guardFor(script).run()
        XCTAssertFalse(script.signedOut)
    }

    func testA503FromTheHomeserverIsNotARefusal() async {
        let guardian = guardFor(Script(sdk: [refresh502], whoami: [(503, Data())]))
        let verdict = await guardian.check()
        XCTAssertEqual(verdict, .unreachable)
    }

    func testSoftLogoutIsNotTheEnd() async {
        let guardian = guardFor(Script(sdk: [refresh502], whoami: [(401, soft401)]))
        let verdict = await guardian.check()
        XCTAssertEqual(verdict, .unreachable)
    }

    func testTheTokenWorkingAgainIsValid() async {
        let guardian = guardFor(Script(sdk: [refresh502], whoami: [(200, Data(#"{"user_id":"@tim:x"}"#.utf8))]))
        let verdict = await guardian.check()
        XCTAssertEqual(verdict, .valid)
    }

    func testInvalidGrantSignsOutAtOnce() async {
        let script = Script(sdk: [#"RefreshToken(ServerResponse(error: invalid_grant))"#])
        let guardian = guardFor(script)
        guardian.suspect(from: "/_matrix/client/v3/notifications", errcode: "M_UNKNOWN_TOKEN")
        await guardian.run()
        XCTAssertTrue(script.signedOut)
        XCTAssertEqual(script.reasons.last, "invalid_grant")
        XCTAssertEqual(script.sleeps, [])
        // The server hears why, before the session ends.
        XCTAssertEqual(script.reports.last?["out"], "signout_invalid_grant")
        XCTAssertEqual(script.reports.last?["from"], "/_matrix/client/v3/notifications")
        XCTAssertEqual(script.reports.last?["err"], "M_UNKNOWN_TOKEN")
    }

    /// Our own call with an expired token: the SDK refreshes, the call may go again, no logout.
    func testAnExpiredTokenOnOurOwnCallRefreshesAndRetries() async {
        let script = Script(sdk: [nil])
        let ok = await guardFor(script).confirmValid(path: "/_matrix/client/v3/pushrules/global/override/x")
        XCTAssertTrue(ok)
        XCTAssertFalse(script.signedOut)
    }

    func testSoftLogoutNeverSignsOut() async {
        let script = Script(sdk: [refresh502, refresh502, refresh502, refresh502, nil], whoami: [(401, soft401)])
        await guardFor(script).run()
        XCTAssertFalse(script.signedOut, "a soft logout signed out")
        XCTAssertEqual(script.reports.last?["out"], "kept")
    }

    func testPathsAreReportedWithoutIDs() {
        XCTAssertEqual(AuthGuard.shape(of: "/_matrix/client/v3/rooms/!abc:iphoneblog.de/event/$ev?x=1"),
                       "/_matrix/client/v3/rooms/*/event/*")
        XCTAssertEqual(AuthGuard.shape(of: "/_matrix/client/v3/user/%40tim%3Aiphoneblog.de/account_data/x"),
                       "/_matrix/client/v3/user/*/account_data/x")
    }

    func testARefusalWhileMASAnswersSignsOutOnTheThirdTime() async {
        let script = Script(sdk: [refresh502], whoami: [(401, hard401)], issuer: [true])
        await guardFor(script).run()
        XCTAssertTrue(script.signedOut)
        XCTAssertEqual(script.sleeps, [.seconds(2), .seconds(4)], "signed out before three refusals")
    }

    func testAnOutageBetweenRefusalsStartsTheCountAgain() async {
        let script = Script(sdk: [refresh502, refresh502, refresh502, refresh502, nil],
                            whoami: [(401, hard401)], issuer: [true, true, false, true, true])
        await guardFor(script).run()
        XCTAssertFalse(script.signedOut, "refusals around an outage were counted together")
    }
}
