import XCTest
@testable import iphoneblog

/// The brand is spelt "iPhoneBlog" wherever a person reads it (Alex, approved by Thorsten on
/// 2026-11-20): under the icon, as the push title, in Element X's texts. Domains stay lower-case.
final class BrandSpellingTests: XCTestCase {
    func testAppNameIsSpeltIPhoneBlog() {
        XCTAssertEqual(Brand.appName, "iPhoneBlog")
    }
}
