import XCTest
import UIKit
import DeltaCore
@testable import Delta

@MainActor final class AppearanceIntegrationTests: XCTestCase {
    func testMinimalDrawingPreservesNativeAndCustomizedGeometryAndInput() throws {
        let native = try XCTUnwrap(DeltaCore.ControllerSkin.standardControllerSkin(for: System.gba.gameType))
        for orientation in [DeltaCore.ControllerSkin.Orientation.portrait, .landscape] {
            let traits = DeltaCore.ControllerSkin.Traits(device: .iphone, displayType: .standard, orientation: orientation)
            let canvas = orientation == .portrait ? CGSize(width: 390, height: 280) : CGSize(width: 844, height: 390)
            let items = try XCTUnwrap(native.items(for: traits))
            let first = try XCTUnwrap(items.first(where: { $0.kind == .button }))
            let placed = BoundPlacedControllerSkin(base: native, layout: .init(positions: [first.id: .init(x: 0.7, y: 0.65, scale: 1.1)]), canvasSize: canvas)
            for base in [native as ControllerSkinProtocol, placed as ControllerSkinProtocol] {
                let light = BoundMinimalControllerSkin(base: base, canvasSize: canvas, traits: UITraitCollection(userInterfaceStyle: .light))
                let dark = BoundMinimalControllerSkin(base: base, canvasSize: canvas, traits: UITraitCollection(userInterfaceStyle: .dark))
                let original = try XCTUnwrap(base.items(for: traits)), themed = try XCTUnwrap(light.items(for: traits))
                XCTAssertEqual(themed.map(\.id), original.map(\.id))
                XCTAssertEqual(themed.map(\.frame), original.map(\.frame))
                for (actual, expected) in zip(themed, original) {
                    XCTAssertTrue(actual.extendedFrame.contains(expected.extendedFrame))
                    if actual.kind == .button {
                        XCTAssertGreaterThanOrEqual(actual.extendedFrame.width * canvas.width, 44 - 0.001)
                        XCTAssertGreaterThanOrEqual(actual.extendedFrame.height * canvas.height, 44 - 0.001)
                    } else { XCTAssertEqual(actual.extendedFrame, expected.extendedFrame) }
                }
                XCTAssertEqual(themed.map { $0.inputs.allInputs.map(\.stringValue) }, original.map { $0.inputs.allInputs.map(\.stringValue) })
                XCTAssertEqual(light.gameScreenFrame(for: traits), base.gameScreenFrame(for: traits))
                XCTAssertEqual(light.aspectRatio(for: traits), base.aspectRatio(for: traits))
                XCTAssertNotEqual(light.identifier, dark.identifier)
                let normal = try XCTUnwrap(light.image(for: traits, preferredSize: .small))
                XCTAssertEqual(normal.size, canvas)
                XCTAssertNotEqual(normal.pngData(), dark.image(for: traits, preferredSize: .small)?.pngData())
                XCTAssertNotEqual(normal.pngData(), light.pressedImage(for: traits, preferredSize: .small)?.pngData())
            }
        }
    }
    func testFeedbackUsesExistingDeltaSettingsAndNotifications() {
        let buttons = Settings.isButtonHapticFeedbackEnabled, sticks = Settings.isThumbstickHapticFeedbackEnabled
        defer { Settings.isButtonHapticFeedbackEnabled = buttons; Settings.isThumbstickHapticFeedbackEnabled = sticks }
        let expectation = expectation(forNotification: Settings.didChangeNotification, object: nil) { note in
            (note.userInfo?[Settings.NotificationUserInfoKey.name] as? Settings.Name) == .isButtonHapticFeedbackEnabled
        }
        Settings.isButtonHapticFeedbackEnabled = false
        Settings.isThumbstickHapticFeedbackEnabled = false
        XCTAssertFalse(Settings.isButtonHapticFeedbackEnabled)
        XCTAssertFalse(Settings.isThumbstickHapticFeedbackEnabled)
        Settings.isButtonHapticFeedbackEnabled = true
        Settings.isThumbstickHapticFeedbackEnabled = true
        XCTAssertTrue(Settings.isButtonHapticFeedbackEnabled)
        XCTAssertTrue(Settings.isThumbstickHapticFeedbackEnabled)
        wait(for: [expectation], timeout: 1)
    }
}

extension AppearanceIntegrationTests {
    func testBackendDetailsComeFromSelectedGBAIntegration() throws {
        let core = try XCTUnwrap(DeltaCore.Delta.core(for: System.gba.gameType))
        let details = BoundEmulationDetails(packageName: core.name, packageIdentifier: core.identifier, packageVersion: core.version)
        XCTAssertEqual(details.packageName, "GBADeltaCore")
        XCTAssertEqual(details.packageIdentifier, "com.rileytestut.GBADeltaCore")
        XCTAssertNil(core.version, "Pinned wrapper exposes no release version; source revision must be used")
        XCTAssertEqual(details.packageBuild, "Pinned source 869c34aeca9d")
        XCTAssertEqual(details.engineName, "VBA-M")
        XCTAssertEqual(details.engineRevision, "453fa0decf179360926fb417725a794aa496d6e3")
    }
}

@MainActor final class GameImportPolicyTests: XCTestCase {
    func testSupportedExtensionsAndUnsupportedDataAreValidatedAfterPicker() async throws {
        XCTAssertEqual(GameType(fileExtension: "gba"), System.gba.gameType)
        XCTAssertEqual(GameType(fileExtension: "GBA"), System.gba.gameType)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try Set(["txt", "pdf", "sav"].map { ext -> URL in
            let url = directory.appendingPathComponent("Unsupported.\(ext)")
            try Data("Original unsupported test data".utf8).write(to: url)
            return url
        })
        let result = await withCheckedContinuation { continuation in
            DatabaseManager.shared.importGames(at: urls) { games, errors in
                continuation.resume(returning: (games, errors))
            }
        }
        XCTAssertTrue(result.0.isEmpty)
        XCTAssertEqual(result.1.count, urls.count)
    }
}
