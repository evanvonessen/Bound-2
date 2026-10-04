import XCTest
import UIKit
@testable import Delta

@MainActor final class TypeChartViewTests: XCTestCase {
    func testPortraitInitialHeightFitZoomPanAndViewportReset() throws {
        let scroll = BoundPortraitChartScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 240))
        scroll.layoutIfNeeded()
        let image = try XCTUnwrap(scroll.subviews.compactMap { $0 as? UIImageView }.first)
        let asset = try XCTUnwrap(image.image)
        let initial = scroll.zoomScale
        XCTAssertEqual(image.frame.height, scroll.bounds.height, accuracy: 0.1)
        XCTAssertEqual(image.frame.width / image.frame.height, asset.size.width / asset.size.height, accuracy: 0.001)
        XCTAssertEqual(scroll.accessibilityIdentifier, "bound.type-chart")
        XCTAssertTrue(scroll.accessibilityValue?.contains("viewportHeight=240.00") == true)
        scroll.setZoomScale(initial * 2, animated: false)
        scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale, initial * 2, accuracy: 0.0001)
        XCTAssertEqual(image.frame.height, 480, accuracy: 0.1)
        scroll.setContentOffset(CGPoint(x: 20, y: 50), animated: false)
        XCTAssertTrue(scroll.accessibilityValue?.contains("imageY=-50.00") == true)
        // Orientation/layout changes reset content instead of carrying stale offsets.
        scroll.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        XCTAssertEqual(image.frame.height, 180, accuracy: 0.1)
        XCTAssertEqual(scroll.zoomScale, 180 / asset.size.height, accuracy: 0.0001)
        XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 0.1)
        let reopened = BoundPortraitChartScrollView(frame: scroll.frame)
        reopened.layoutIfNeeded()
        XCTAssertEqual(reopened.zoomScale, scroll.zoomScale, accuracy: 0.0001)
        XCTAssertEqual(reopened.contentOffset, scroll.contentOffset)
    }
}
