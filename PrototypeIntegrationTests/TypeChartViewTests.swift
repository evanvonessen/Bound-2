import XCTest
import UIKit
@testable import Delta

@MainActor final class TypeChartViewTests: XCTestCase {
    func testExpandedViewportInitiallyClearsIslandAndShowsChartBottom() throws {
        let scroll = BoundPortraitChartScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 240))
        scroll.topInset = 62
        scroll.layoutIfNeeded()
        let image = try XCTUnwrap(scroll.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(scroll.bounds.height, 240)
        XCTAssertEqual(image.frame.height, 178, accuracy: 0.1)
        let visibleFrame = image.frame.offsetBy(dx: -scroll.contentOffset.x, dy: -scroll.contentOffset.y)
        XCTAssertEqual(visibleFrame.minY, 62, accuracy: 0.1)
        XCTAssertEqual(visibleFrame.maxY, 240, accuracy: 0.1)
        XCTAssertEqual(scroll.backgroundColor, .black)
        XCTAssertTrue(scroll.bouncesZoom)
        let source = try XCTUnwrap(image.image)
        XCTAssertEqual(scroll.minimumZoomScale, min(402 / source.size.width, 178 / source.size.height), accuracy: 0.0001)
        scroll.setZoomScale(scroll.minimumZoomScale, animated: false)
        XCTAssertLessThanOrEqual(image.frame.width, scroll.bounds.width + 0.1)
        XCTAssertLessThanOrEqual(image.frame.height, 178.1)
        scroll.setZoomScale(178 / source.size.height, animated: false)
        let initial = scroll.zoomScale
        scroll.setZoomScale(initial * 2, animated: false)
        scroll.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        XCTAssertGreaterThan(image.frame.height, scroll.bounds.height)
        XCTAssertEqual(image.frame.minY-scroll.contentOffset.y, 0, accuracy: 0.1)
    }
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
