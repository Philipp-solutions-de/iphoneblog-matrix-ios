import XCTest
import UserNotifications
@testable import iphoneblog

/// Report, block, account deletion and the push primer: the decisions behind the App Review
/// items of iphoneblog-wordpress docs/TODO.md, "App Store readiness".
final class ModerationTests: XCTestCase {
    func testReportUserPathEscapesTheMatrixID() {
        XCTAssertEqual(Moderation.reportUserPath("@anna.mueller:iphoneblog.de"),
                       "/_matrix/client/v3/users/%40anna.mueller%3Aiphoneblog.de/report")
        // An ID that would change the path is escaped, not followed.
        XCTAssertEqual(Moderation.reportUserPath("@a/../b:iphoneblog.de"),
                       "/_matrix/client/v3/users/%40a%2F..%2Fb%3Aiphoneblog.de/report")
    }

    func testReportUserPathRefusesWhatIsNoMatrixID() {
        XCTAssertNil(Moderation.reportUserPath("anna.mueller"))
        XCTAssertNil(Moderation.reportUserPath("@anna"))
    }

    func testReportTextCarriesReasonAndNote() {
        XCTAssertEqual(Moderation.reportText(.spam, note: "  "), "Spam oder Werbung")
        XCTAssertEqual(Moderation.reportText(.abuse, note: " beleidigt mich seit gestern\n"),
                       "Beleidigung oder Belästigung: beleidigt mich seit gestern")
        XCTAssertEqual(Moderation.reportText(.other, note: String(repeating: "x", count: 5000)).count,
                       "Etwas anderes: ".count + 1000)
    }

    func testReportUserBodyIsJSON() throws {
        let json = try JSONSerialization.jsonObject(with: Moderation.reportUserBody("Spam oder Werbung")) as? [String: String]
        XCTAssertEqual(json, ["reason": "Spam oder Werbung"])
    }

    /// The guard fires: nobody reports or blocks themselves.
    func testNobodyModeratesThemselves() {
        XCTAssertFalse(Moderation.canModerate(userID: "@kyrios:iphoneblog.de", ownUserID: "@kyrios:iphoneblog.de"))
        XCTAssertTrue(Moderation.canModerate(userID: "@anna.mueller:iphoneblog.de", ownUserID: "@kyrios:iphoneblog.de"))
    }

    func testDeletionOpensTheWebsitePageInAppView() {
        XCTAssertEqual(AccountDeletionView.deletionURL(blogBase: URL(string: "https://www.iphoneblog.de/")!),
                       URL(string: "https://www.iphoneblog.de/konto/loeschen/?app=1"))
    }

    /// The primer shows once, and never when iOS was asked already: the guard fires for each.
    func testPushPrimerOnlyBeforeIOSAsked() {
        XCTAssertTrue(PushPrimer.shouldShow(status: .notDetermined, alreadyShown: false))
        XCTAssertFalse(PushPrimer.shouldShow(status: .notDetermined, alreadyShown: true))
        XCTAssertFalse(PushPrimer.shouldShow(status: .denied, alreadyShown: false))
        XCTAssertFalse(PushPrimer.shouldShow(status: .authorized, alreadyShown: false))
    }
}
