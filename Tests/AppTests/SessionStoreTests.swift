import MatrixRustSDK
import XCTest
@testable import iphoneblog

final class SessionStoreTests: XCTestCase {
    func testBrandPointsAtOurServer() {
        XCTAssertEqual(Brand.serverName, "iphoneblog.de")
        XCTAssertTrue(Brand.homeserverURL.hasPrefix("https://"))
        XCTAssertTrue(Brand.oauthRedirectURI.hasPrefix(Brand.oauthRedirectScheme + ":"))
        XCTAssertEqual(Brand.pusherAppID, Brand.bundleID + ".ios.prod")
        XCTAssertLessThanOrEqual(Brand.appName.count, 12)
    }

    /// MAS accepts a custom redirect scheme only when it is the reverse of the client URI's host.
    func testRedirectSchemeIsReverseOfClientHost() throws {
        let host = try XCTUnwrap(URL(string: Brand.oauthClientURI)?.host())
        let reversed = host.split(separator: ".").reversed().joined(separator: ".")
        XCTAssertEqual(Brand.oauthRedirectScheme, reversed)
    }

    func testOAuthPagesShareTheClientHost() throws {
        let host = URL(string: Brand.oauthClientURI)?.host()
        for page in [Brand.oauthLogoURI, Brand.oauthTermsURI, Brand.oauthPolicyURI] {
            XCTAssertEqual(URL(string: page)?.host(), host, page)
        }
    }

    func testStoredSessionRoundTrip() throws {
        let stored = StoredSession(.init(accessToken: "a", refreshToken: "r", userId: "@x:iphoneblog.de",
                                         deviceId: "D", homeserverUrl: "https://example.org",
                                         oauthData: nil, slidingSyncVersion: .native),
                                   storeID: "s")
        let data = try JSONEncoder().encode(stored)
        let back = try JSONDecoder().decode(StoredSession.self, from: data)
        XCTAssertEqual(back, stored)
        XCTAssertEqual(back.sdkSession.slidingSyncVersion, .native)
    }
}
