import XCTest
import UIKit
@testable import Delta

@MainActor
final class CompanionCycleButtonTests: XCTestCase {
    func testPortraitMirrorKeepsDefaultAndAvoidsMovedInput() throws {
        let canvas = CGRect(x: 0, y: 0, width: 390, height: 800)
        let menu = CGRect(x: 20, y: 740, width: 20, height: 20)
        let button = BoundCompanionCycleButton()
        button.configure(menuFrame: menu, controllerFrame: canvas, landscape: false, minimal: false,
                         content: .friend, canvas: canvas, occupied: [menu])
        XCTAssertEqual(button.frame.midX, 360, accuracy: 0.001)
        XCTAssertEqual(button.frame.midY, 750, accuracy: 0.001)
        let movedA = button.frame.insetBy(dx: -4, dy: -4)
        button.configure(menuFrame: menu, controllerFrame: canvas, landscape: false, minimal: false,
                         content: .notes, canvas: canvas, occupied: [menu, movedA])
        XCTAssertFalse(button.isHidden); XCTAssertTrue(canvas.contains(button.frame))
        XCTAssertFalse(button.frame.intersects(menu)); XCTAssertFalse(button.frame.intersects(movedA))
        XCTAssertEqual(button.accessibilityValue, "Notes")
    }
    func testLandscapeChecksCollisionAfterEdgeClamping() throws {
        let canvas = CGRect(x: 50, y: 0, width: 700, height: 350)
        let menu = CGRect(x: 680, y: 8, width: 60, height: 30)
        let blocked = CGRect(x: 610, y: 0, width: 140, height: 70)
        let button = BoundCompanionCycleButton()
        button.configure(menuFrame: menu, controllerFrame: canvas, landscape: true, minimal: false,
                         content: .types, canvas: canvas, occupied: [blocked])
        XCTAssertFalse(button.isHidden); XCTAssertTrue(canvas.contains(button.frame))
        XCTAssertFalse(button.frame.intersects(blocked)); XCTAssertEqual(button.accessibilityValue, "Types")
    }
    func testNoClearSpaceDoesNotStealNativeInputsAndRecoversAfterReset() {
        let canvas = CGRect(x: 0, y: 0, width: 200, height: 100)
        let button = BoundCompanionCycleButton()
        let menu = CGRect(x: 10, y: 10, width: 20, height: 20)
        button.configure(menuFrame: menu, controllerFrame: canvas, landscape: false, minimal: false,
                         content: .friend, canvas: canvas, occupied: [canvas])
        XCTAssertTrue(button.isHidden); XCTAssertFalse(button.isUserInteractionEnabled); XCTAssertEqual(button.frame, .zero)
        button.configure(menuFrame: menu, controllerFrame: canvas, landscape: false, minimal: false,
                         content: .friend, canvas: canvas, occupied: [menu])
        XCTAssertFalse(button.isHidden); XCTAssertTrue(button.isUserInteractionEnabled)
    }
}
