import XCTest
@testable import iphoneblog

/// The static MAS client: WordPress's web-login accepts only its tokens.
@MainActor
final class OAuthConfigurationTests: XCTestCase {
    func testEmptyClientIDRegistersDynamically() {
        XCTAssertEqual(AppModel.staticRegistrations(clientID: ""), [:])
    }

    func testClientIDCoversHomeserverAndIssuer() {
        let registrations = AppModel.staticRegistrations(clientID: "01TESTCLIENT")
        for key in [Brand.homeserverURL, Brand.oauthIssuerURL] {
            XCTAssertEqual(registrations[key], "01TESTCLIENT", key)
        }
        XCTAssertTrue(registrations.values.allSatisfy { $0 == "01TESTCLIENT" })
    }
}
