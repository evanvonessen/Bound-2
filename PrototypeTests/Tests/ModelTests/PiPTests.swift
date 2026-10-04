import Foundation
import CoreGraphics
import XCTest
@testable import Models
final class PiPTests: XCTestCase {
    @MainActor func testPreferencesPersistIndependentContentAndSharedCorner() throws {
        let suite = "BoundPiPTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BoundPiPPreferences(defaults: defaults)
        XCTAssertEqual(model.corner, .topRight)
        for content in BoundPiPContent.allCases {
            XCTAssertEqual(model.scale(for: content), 1)
            XCTAssertEqual(model.opacity(for: content), 1)
        }
        model.corner = .bottomLeft
        model.setScale(0.7, for: .friend); model.setScale(1.25, for: .types)
        model.setTransparency(0.75, for: .notes)
        let restarted = BoundPiPPreferences(defaults: defaults)
        XCTAssertEqual(restarted.corner, .bottomLeft)
        XCTAssertEqual(restarted.scale(for: .friend), 0.7)
        XCTAssertEqual(restarted.scale(for: .types), 1.25)
        XCTAssertEqual(restarted.scale(for: .notes), 1)
        XCTAssertEqual(restarted.opacity(for: .notes), 0.25)
        XCTAssertEqual(restarted.opacity(for: .friend), 1)
        restarted.setScale(.nan, for: .friend)
        XCTAssertEqual(restarted.scale(for: .friend), 0.7)
        restarted.setScale(20, for: .types)
        XCTAssertEqual(restarted.scale(for: .types), 1.4)
    }
    @MainActor func testVerticalOpacityMappingMatchesOriginalBound() {
        XCTAssertEqual(BoundPiPPreferences.opacity(start: 1, verticalTranslation: 50, panelHeight: 100), 0.5)
        XCTAssertEqual(BoundPiPPreferences.opacity(start: 0.5, verticalTranslation: -50, panelHeight: 100), 1)
        XCTAssertEqual(BoundPiPPreferences.opacity(start: 0.5, verticalTranslation: 500, panelHeight: 100), 0)
    }
    func testCornersClampAndDirectionalSnap() {
        let viewport = CGRect(x: 100, y: 20, width: 600, height: 400)
        let layout = BoundPiPLayout(viewport: viewport, baseSize: CGSize(width: 216, height: 144), scale: 1.4)
        for corner in BoundPiPCorner.allCases {
            let center = layout.center(corner)
            let frame = CGRect(x: center.x - layout.size.width/2, y: center.y - layout.size.height/2,
                               width: layout.size.width, height: layout.size.height)
            XCTAssertTrue(viewport.contains(frame))
            let clamp = layout.clampedCenter(from: corner, translation: CGSize(width: 9999, height: -9999))
            XCTAssertEqual(clamp.x, viewport.maxX - 8 - layout.size.width/2)
            XCTAssertEqual(clamp.y, viewport.minY + 8 + layout.size.height/2)
        }
        XCTAssertEqual(layout.destination(from: .topRight, translation: CGSize(width: -71, height: 56)), .bottomLeft)
        XCTAssertEqual(layout.destination(from: .topRight, translation: CGSize(width: -70, height: 55)), .topRight)
        XCTAssertEqual(layout.hiddenSide(from: .topRight, translation: CGSize(width: 51, height: 0), endX: 681), .right)
        XCTAssertNil(layout.hiddenSide(from: .topRight, translation: CGSize(width: 50, height: 0), endX: 700))
        XCTAssertEqual(layout.hiddenSide(from: .bottomLeft, translation: CGSize(width: -400, height: 0)), .left)
    }
}
