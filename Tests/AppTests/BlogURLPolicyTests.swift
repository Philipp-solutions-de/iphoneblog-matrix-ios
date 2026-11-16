import XCTest
@testable import iphoneblog

/// The Blog tab's web view stays on iphoneblog.de (BlogURLPolicy): the age rating depends on it.
final class BlogURLPolicyTests: XCTestCase {
    private let live = "www.iphoneblog.de"
    private let beta = "beta.iphoneblog.de"

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testBlogPagesStay() {
        XCTAssertEqual(BlogURLPolicy.decide(url("https://www.iphoneblog.de/2026/11/16/kw47/?app=1"), mainFrame: true, blogHost: live), .allow)
        XCTAssertEqual(BlogURLPolicy.decide(url("https://iphoneblog.de/konto/?app=1"), mainFrame: true, blogHost: live), .allow)
        XCTAssertEqual(BlogURLPolicy.decide(url("https://beta.iphoneblog.de/anmelden/?app=1"), mainFrame: true, blogHost: beta), .allow)
    }

    /// The case the policy exists for: a redirect off the blog (Stripe's portal from /konto/,
    /// a short link in an article) must not open in the app's web view.
    func testRedirectOffTheBlogOpensOutside() {
        XCTAssertEqual(BlogURLPolicy.decide(url("https://billing.stripe.com/p/session/live_YWNjdF8xTjRx"), mainFrame: true, blogHost: live), .openOutside)
        XCTAssertEqual(BlogURLPolicy.decide(url("https://www.google.com/search?q=iphone"), mainFrame: true, blogHost: live), .openOutside)
        // A look-alike host is not the blog.
        XCTAssertEqual(BlogURLPolicy.decide(url("https://www.iphoneblog.de.example.org/"), mainFrame: true, blogHost: live), .openOutside)
        XCTAssertEqual(BlogURLPolicy.decide(url("http://evil-iphoneblog.de/"), mainFrame: true, blogHost: live), .openOutside)
    }

    func testStaffGateOnlyOnBeta() {
        let gate = url("https://auth.phso.de/?rd=https%3A%2F%2Fbeta.iphoneblog.de%2F")
        XCTAssertEqual(BlogURLPolicy.decide(gate, mainFrame: true, blogHost: beta), .allow)
        XCTAssertEqual(BlogURLPolicy.decide(gate, mainFrame: true, blogHost: live), .openOutside)
    }

    func testEmbedsInFramesLoad() {
        XCTAssertEqual(BlogURLPolicy.decide(url("https://www.youtube-nocookie.com/embed/abc"), mainFrame: false, blogHost: live), .allow)
        XCTAssertEqual(BlogURLPolicy.decide(url("about:blank"), mainFrame: false, blogHost: live), .allow)
    }

    func testOtherSchemesAreRefused() {
        XCTAssertEqual(BlogURLPolicy.decide(url("about:blank"), mainFrame: true, blogHost: live), .allow)
        XCTAssertEqual(BlogURLPolicy.decide(url("data:text/html,<h1>x</h1>"), mainFrame: true, blogHost: live), .cancel)
        XCTAssertEqual(BlogURLPolicy.decide(url("file:///etc/hosts"), mainFrame: true, blogHost: live), .cancel)
        XCTAssertEqual(BlogURLPolicy.decide(url("javascript:alert(1)"), mainFrame: false, blogHost: live), .cancel)
    }
}
