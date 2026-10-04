import XCTest
import CoreGraphics
@testable import Models
final class TypeChartGeometryTests: XCTestCase {
    func testInitialScaleFitsHeightInsteadOfWidthAndPreservesAspect() throws {
        let image = CGSize(width: 1000, height: 500), viewport = CGSize(width: 300, height: 200)
        let model = try XCTUnwrap(BoundTypeChartGeometry(image: image, viewport: viewport))
        XCTAssertEqual(model.initialScale, 0.4)
        XCTAssertEqual(image.height * model.initialScale, viewport.height)
        XCTAssertEqual(image.width * model.initialScale, 400)
        XCTAssertEqual(model.minimumScale, 0.2)
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
