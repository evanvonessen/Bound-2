import XCTest
import UIKit
import DeltaCore
@testable import Delta

@MainActor
final class StockControlAndGestureTests: XCTestCase {
    func testLandscapeStockMenuMovesBelowLeftShoulderWithoutChangingNativeInputOrSize() throws {
        let base = try XCTUnwrap(DeltaCore.ControllerSkin.standardControllerSkin(for: System.gba.gameType))
        let traits = DeltaCore.ControllerSkin.Traits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape)
        let old = try XCTUnwrap(base.items(for: traits))
        let skin = BoundStockControllerSkin(base: base, canvasSize: CGSize(width: 844, height: 390))
        let items = try XCTUnwrap(skin.items(for: traits))
        let menu = try XCTUnwrap(items.first { $0.inputs.allInputs.contains { $0.stringValue == "menu" } })
        let nativeMenu = try XCTUnwrap(old.first { $0.id == menu.id })
        let left = try XCTUnwrap(items.first { $0.inputs.allInputs.contains { $0.stringValue == "l" } })
        XCTAssertEqual(menu.frame.size, nativeMenu.frame.size)
        XCTAssertEqual(menu.extendedFrame.size, nativeMenu.extendedFrame.size)
        XCTAssertEqual(menu.frame.midX, left.frame.midX, accuracy: 0.001)
        XCTAssertEqual((menu.extendedFrame.minY-left.extendedFrame.maxY)*390, 10, accuracy: 0.001)
        for item in items where item.id != menu.id { XCTAssertEqual(item.frame, old.first { $0.id == item.id }?.frame) }
        let custom = BoundPlacedControllerSkin(base: skin, layout: .init(positions: [menu.id: .init(x: 0.5, y: 0.8, scale: 1)]), canvasSize: CGSize(width: 844, height: 390))
        XCTAssertEqual(custom.items(for: traits)?.first { $0.id == menu.id }?.frame.midX, 0.5)
        XCTAssertEqual(custom.items(for: traits)?.first { $0.id == menu.id }?.frame.midY, 0.8)
    }
    func testStockMenuCompleteTouchTargetStaysInsideLandscapeSafeArea() throws {
        let base = try XCTUnwrap(DeltaCore.ControllerSkin.standardControllerSkin(for: System.gba.gameType))
        let traits = DeltaCore.ControllerSkin.Traits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape)
        let size = CGSize(width: 844, height: 390)
        let original = try XCTUnwrap(base.items(for: traits))
        for inset in [UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 0), UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 47)] {
            let skin = BoundStockControllerSkin(base: base, canvasSize: size, contentInsets: inset)
            let items = try XCTUnwrap(skin.items(for: traits))
            let menu = try XCTUnwrap(items.first { $0.inputs.allInputs.contains { $0.stringValue == "menu" } })
            let old = try XCTUnwrap(original.first { $0.id == menu.id })
            let hit = menu.extendedFrame.applying(.init(scaleX: size.width, y: size.height))
            XCTAssertGreaterThanOrEqual(hit.minX, inset.left-0.001)
            XCTAssertLessThanOrEqual(hit.maxX, size.width-inset.right+0.001)
            XCTAssertEqual(menu.frame.size, old.frame.size)
            XCTAssertEqual(menu.extendedFrame.size, old.extendedFrame.size)
            for item in items where item.id != menu.id { XCTAssertEqual(item.frame, original.first { $0.id == item.id }?.frame) }
        }
    }
    func testFingerCountChangesCannotCommitUnwantedMovementResizeOrOpacity() {
        for required in [1, 2, 3] {
            var gate = BoundPiPTouchCountGate()
            XCTAssertEqual(gate.update(phase: .began, touches: required, required: required), .deliver)
            XCTAssertEqual(gate.update(phase: .changed, touches: required+1, required: required), .cancel)
            XCTAssertEqual(gate.update(phase: .changed, touches: required, required: required), .ignore)
            XCTAssertEqual(gate.update(phase: .ended, touches: 0, required: required), .ignore)
            XCTAssertEqual(gate.update(phase: .began, touches: required, required: required), .deliver)
            XCTAssertEqual(gate.update(phase: .ended, touches: 0, required: required), .deliver)
        }
    }

    func testLandscapePiPReservesAllStockAndCompanionHitRegions() throws {
        let base = try XCTUnwrap(DeltaCore.ControllerSkin.standardControllerSkin(for: System.gba.gameType))
        let traits = DeltaCore.ControllerSkin.Traits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape)
        let canvas = CGRect(x: 0, y: 0, width: 844, height: 390)
        for insets in [UIEdgeInsets(top: 0, left: 47, bottom: 21, right: 0), UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 47)] {
            let skin = BoundStockControllerSkin(base: base, canvasSize: canvas.size, contentInsets: insets)
            let items = try XCTUnwrap(skin.items(for: traits))
            let transform = CGAffineTransform(scaleX: canvas.width, y: canvas.height)
            let occupied = items.map { $0.extendedFrame.applying(transform) }
            let menu = try XCTUnwrap(items.first { $0.inputs.allInputs.contains { $0.stringValue == "menu" } })
            let right = try XCTUnwrap(items.first { $0.inputs.allInputs.contains { $0.stringValue == "r" } })
            let game = CGRect(x: 129.5, y: 0, width: 585, height: 390)
            for minimal in [false, true] {
                let cycle = BoundCompanionCycleButton(frame: .zero)
                cycle.configure(menuFrame: menu.frame.applying(transform), controllerFrame: canvas,
                    landscape: true, minimal: minimal, content: .types, canvas: canvas.inset(by: insets),
                    occupied: occupied, rightShoulderFrame: right.extendedFrame.applying(transform),
                    menuHitSize: menu.extendedFrame.applying(transform).size)
                XCTAssertFalse(cycle.isHidden)
                for scale: CGFloat in [0.65, 1.4] {
                    let layout = BoundPiPLayout(viewport: game, baseSize: CGSize(width: 210.6, height: 140.4), scale: scale,
                                              occupied: occupied + [cycle.frame])
                    XCTAssertGreaterThan(layout.size.width, 100)
                    XCTAssertEqual(layout.size.width/layout.size.height, 1.5, accuracy: 0.001)
                    for corner in BoundPiPCorner.allCases {
                        let center = layout.center(corner)
                        let panel = CGRect(x: center.x-layout.size.width/2, y: center.y-layout.size.height/2,
                                           width: layout.size.width, height: layout.size.height)
                        XCTAssertTrue(game.contains(panel))
                        for target in occupied + [cycle.frame] { XCTAssertFalse(panel.intersects(target)) }
                    }
                }
            }
        }
    }

}
