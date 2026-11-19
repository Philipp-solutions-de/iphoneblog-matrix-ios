import XCTest
@testable import iphoneblog

/// The profile picture's upload (AvatarCrop), as agreed with the web app: square, 512 px at most,
/// never under 128, no empty space, zoom 1× to 4×.
final class AvatarCropTests: XCTestCase {
    private func image(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testLargePictureBecomes512Pixels() throws {
        let result = try XCTUnwrap(AvatarCrop.render(image(3000, 2000), zoom: 1, offset: .zero, view: 300))
        XCTAssertEqual(result.image.size, CGSize(width: 512, height: 512))
        XCTAssertEqual(result.image.scale, 1, "points are pixels: at 3× this was 1536 px")
        XCTAssertEqual(UIImage(data: result.jpeg)?.size, CGSize(width: 512, height: 512))
    }

    func testSmallPictureKeepsItsSizeAndIsNotBlownUp() throws {
        XCTAssertEqual(try XCTUnwrap(AvatarCrop.render(image(300, 200), zoom: 1, offset: .zero, view: 300)).image.size,
                       CGSize(width: 200, height: 200))
        XCTAssertEqual(try XCTUnwrap(AvatarCrop.render(image(100, 80), zoom: 1, offset: .zero, view: 300)).image.size,
                       CGSize(width: 128, height: 128), "never under 128 px")
    }

    func testZoomShowsAQuarterAtFourTimesAndNoMore() {
        let visible = AvatarCrop.visibleRect(image: CGSize(width: 2000, height: 1000), zoom: 8, offset: .zero, view: 300)
        XCTAssertEqual(visible.width, 250, accuracy: 0.01, "zoom stops at 4×")
        XCTAssertEqual(visible.midX, 1000, accuracy: 0.01)
    }

    func testMovingStopsAtTheEdge() {
        // 2000×1000 at 1× in a 300 view: 600 points wide, so 150 spare on each side.
        let clamped = AvatarCrop.clamp(CGSize(width: 900, height: 50), image: CGSize(width: 2000, height: 1000), zoom: 1, view: 300)
        XCTAssertEqual(clamped.width, 150, accuracy: 0.01)
        XCTAssertEqual(clamped.height, 0, accuracy: 0.01, "no spare height at 1×")
        let visible = AvatarCrop.visibleRect(image: CGSize(width: 2000, height: 1000), zoom: 1, offset: CGSize(width: 900, height: 0), view: 300)
        XCTAssertEqual(visible.minX, 0, accuracy: 0.01, "moved right as far as it goes: the left edge")
    }
}
