import Foundation
import XCTest
@testable import Models
final class ControlPlacementTests: XCTestCase {
    func testDeltaIsDefaultAndResetPersistsAcrossInstances() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let store = BoundControlPlacementStore(defaults: defaults)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), .init())
        let custom = BoundControlLayout(positions: ["a": .init(x: 0.2, y: 0.8, scale: 1.1)])
        store.save(custom, skin: "gba", landscape: true)
        XCTAssertEqual(BoundControlPlacementStore(defaults: defaults).read(skin: "gba", landscape: true), custom)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), .init())
        XCTAssertEqual(store.read(skin: "other", landscape: true), .init())
        store.save(.init(), skin: "gba", landscape: true)
        XCTAssertEqual(store.read(skin: "gba", landscape: true), .init())
    }
    func testCachedLayoutTracksExternalEditsInvalidDataAndRemoval() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = BoundControlPlacementStore(defaults: defaults)
        let other = BoundControlPlacementStore(defaults: defaults)
        let first = BoundControlLayout(positions: ["a": .init(x: 0.2, y: 0.8, scale: 1)])
        let second = BoundControlLayout(positions: ["a": .init(x: 0.7, y: 0.6, scale: 1.2)])
        other.save(first, skin: "gba", landscape: false)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), first)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), first)
        other.save(second, skin: "gba", landscape: false)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), second)
        XCTAssertEqual(store.read(skin: "gba", landscape: true), .init())
        let key = "bound.controls.v1.gba.portrait"
        defaults.set(Data("malformed".utf8), forKey: key)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), .init())
        other.save(first, skin: "gba", landscape: false)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), first)
        defaults.removeObject(forKey: key)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), .init())
    }

    func testNormalizedGeometryClampsAndHonorsMinimumSizes() {
        let layout = BoundControlLayout(positions: ["a": .init(x: 1, y: 0, scale: 0.7), "dpad": .init(x: 0, y: 1, scale: 1.4)])
        let canvas = CGSize(width: 390, height: 844)
        let a = layout.frame(id: "a", base: CGRect(x: 10, y: 10, width: 20, height: 20), canvas: canvas, directional: false)
        XCTAssertEqual(a.width, 44); XCTAssertEqual(a.maxX, canvas.width); XCTAssertEqual(a.minY, 0)
        let pad = layout.frame(id: "dpad", base: CGRect(x: 10, y: 10, width: 80, height: 80), canvas: canvas, directional: true)
        XCTAssertEqual(pad.width, 132); XCTAssertEqual(pad.minX, 0); XCTAssertEqual(pad.maxY, canvas.height)
        let tiny = layout.frame(id: "dpad", base: .zero, canvas: CGSize(width: 80, height: 60), directional: true)
        XCTAssertEqual(tiny, CGRect(x: 0, y: 0, width: 80, height: 60))
    }
    func testInvalidDataDoesNotOverrideLastValidLayout() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let store = BoundControlPlacementStore(defaults: defaults)
        let invalid = BoundControlLayout(positions: ["a": .init(x: .infinity, y: 0, scale: 1)])
        XCTAssertFalse(invalid.isValid); store.save(invalid, skin: "gba", landscape: false)
        XCTAssertEqual(store.read(skin: "gba", landscape: false), .init())
        XCTAssertFalse(BoundControlLayout(positions: ["a": .init(x: 0.5, y: 0.5, scale: 1.5)]).isValid)
    }
}
