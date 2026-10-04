import XCTest
import CoreGraphics
@testable import Models
final class TypeChartGeometryTests: XCTestCase {
    func testPortraitChartUsesTopAreaWithoutChangingNativeGameOrController() throws {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let original = BoundPortraitScreenGeometry(bounds: bounds, safeTop: 62,
            controllerSize: CGSize(width: 375, height: 335), gameAspect: CGSize(width: 3, height: 2))
        let chart = BoundTypeChartGeometry.portraitViewport(bounds: bounds, gameFrame: original.game)
        XCTAssertEqual(chart.minY, bounds.minY)
        XCTAssertEqual(chart.maxY, original.game.minY)
        XCTAssertEqual(chart.width, original.game.width)
        XCTAssertGreaterThan(chart.height, original.friend.height)
        XCTAssertEqual(original.game.width / original.game.height, 1.5, accuracy: 0.001)
        XCTAssertEqual(original.controller.maxY, bounds.maxY)
        let fit = try XCTUnwrap(BoundTypeChartGeometry(image: CGSize(width: 1200, height: 900), viewport: chart.size))
        XCTAssertEqual(fit.initialScale * 900, chart.height, accuracy: 0.001)
    }
    func testInitialScaleFitsHeightInsteadOfWidthAndPreservesAspect() throws {
        let image = CGSize(width: 1000, height: 500), viewport = CGSize(width: 300, height: 200)
        let model = try XCTUnwrap(BoundTypeChartGeometry(image: image, viewport: viewport))
        XCTAssertEqual(model.initialScale, 0.4)
        XCTAssertEqual(image.height * model.initialScale, viewport.height)
        XCTAssertEqual(image.width * model.initialScale, 400)
        XCTAssertEqual(model.minimumScale, 0.3)
        XCTAssertEqual(image.width * model.minimumScale, viewport.width)
        XCTAssertLessThanOrEqual(image.height * model.minimumScale, viewport.height)
        XCTAssertEqual(model.maximumScale, 3.2)
    }
    func testSmallContentCenteredAndLargeContentPannableWithoutStretching() {
        let small = BoundTypeChartGeometry.centeredInsets(content: CGSize(width: 200, height: 100), viewport: CGSize(width: 300, height: 200))
        XCTAssertEqual(small.horizontal, 50); XCTAssertEqual(small.vertical, 50)
        let large = BoundTypeChartGeometry.centeredInsets(content: CGSize(width: 600, height: 400), viewport: CGSize(width: 300, height: 200))
        XCTAssertEqual(large.horizontal, 0); XCTAssertEqual(large.vertical, 0)
    }
    func testRejectsInvalidLayoutAndRotationRecalculatesInitialScale() throws {
        XCTAssertNil(BoundTypeChartGeometry(image: .zero, viewport: CGSize(width: 300, height: 200)))
        XCTAssertNil(BoundTypeChartGeometry(image: CGSize(width: 100, height: 100), viewport: CGSize(width: CGFloat.nan, height: 200)))
        let a = try XCTUnwrap(BoundTypeChartGeometry(image: CGSize(width: 100, height: 100), viewport: CGSize(width: 300, height: 200)))
        let b = try XCTUnwrap(BoundTypeChartGeometry(image: CGSize(width: 100, height: 100), viewport: CGSize(width: 200, height: 300)))
        XCTAssertEqual(a.initialScale, 2); XCTAssertEqual(b.initialScale, 3)
    }
}
