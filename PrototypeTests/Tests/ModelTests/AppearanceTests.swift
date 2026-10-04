import Foundation
import XCTest
@testable import Models
final class AppearanceTests: XCTestCase {
    func testNativeDefaultPersistAndResetWithoutChangingOtherPreferences() throws {
        let suite = "BoundAppearanceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = BoundAppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .delta)
        defaults.set(0.4, forKey: "bound.delta.pip.v1.friend.opacity")
        defaults.set(false, forKey: "isButtonHapticFeedbackEnabled")
        preferences.theme = .minimal
        XCTAssertEqual(BoundAppearancePreferences(defaults: defaults).theme, .minimal)
        preferences.reset()
        XCTAssertEqual(preferences.theme, .delta)
        XCTAssertEqual(defaults.double(forKey: "bound.delta.pip.v1.friend.opacity"), 0.4)
        XCTAssertFalse(defaults.bool(forKey: "isButtonHapticFeedbackEnabled"))
    }
    func testUnknownThemeFallsBackToNativeDelta() throws {
        let suite = "BoundAppearanceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: BoundAppearancePreferences.themeKey)
        let preferences = BoundAppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .delta)
        preferences.reset()
        XCTAssertEqual(defaults.string(forKey: BoundAppearancePreferences.themeKey), BoundTheme.delta.rawValue)
    }
}

extension AppearanceTests {
    func testScreenLayoutDefaultsPersistAndResetsRemainIndependent() throws {
        let suite = "BoundScreenLayoutTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = BoundAppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.screenLayout, .bound)
        preferences.screenLayout = .delta
        preferences.theme = .minimal
        XCTAssertEqual(BoundAppearancePreferences(defaults: defaults).screenLayout, .delta)
        preferences.reset()
        XCTAssertEqual(preferences.screenLayout, .delta, "Appearance reset must not replace the saved arrangement")
        preferences.theme = .minimal
        defaults.set(0.4, forKey: "bound.delta.pip.v1.friend.opacity")
        defaults.set("kept", forKey: "bound.controls.v1.test")
        preferences.resetScreenLayout()
        XCTAssertEqual(preferences.screenLayout, .bound)
        XCTAssertEqual(preferences.theme, .minimal)
        XCTAssertEqual(defaults.double(forKey: "bound.delta.pip.v1.friend.opacity"), 0.4)
        XCTAssertEqual(defaults.string(forKey: "bound.controls.v1.test"), "kept")
    }
    func testUnsetDefaultsSurviveReopeningWithoutCreatingSavedChoices() throws {
        let suite = "BoundFreshDefaults." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<2 {
            let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
            let preferences = BoundAppearancePreferences(defaults: reopened)
            XCTAssertEqual(preferences.screenLayout, .bound)
            XCTAssertEqual(preferences.theme, .delta)
            XCTAssertNil(reopened.object(forKey: BoundAppearancePreferences.screenLayoutKey))
            XCTAssertNil(reopened.object(forKey: BoundAppearancePreferences.themeKey))
        }
    }
    func testEveryExplicitArrangementSurvivesReopeningAndScreenResetKeepsFeedback() throws {
        let suite = "BoundSavedDefaults." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "isButtonHapticFeedbackEnabled")
        defaults.set(false, forKey: "isThumbstickHapticFeedbackEnabled")
        let preferences = BoundAppearancePreferences(defaults: defaults)
        preferences.theme = .minimal
        for layout in BoundScreenLayout.allCases {
            preferences.screenLayout = layout
            let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
            XCTAssertEqual(BoundAppearancePreferences(defaults: reopened).screenLayout, layout)
            XCTAssertEqual(BoundAppearancePreferences(defaults: reopened).theme, .minimal)
            XCTAssertFalse(reopened.bool(forKey: "isButtonHapticFeedbackEnabled"))
            XCTAssertFalse(reopened.bool(forKey: "isThumbstickHapticFeedbackEnabled"))
        }
        preferences.screenLayout = .delta
        preferences.resetScreenLayout()
        XCTAssertEqual(preferences.screenLayout, .bound)
        XCTAssertEqual(preferences.theme, .minimal)
        XCTAssertFalse(defaults.bool(forKey: "isButtonHapticFeedbackEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isThumbstickHapticFeedbackEnabled"))
    }
    func testUnknownScreenLayoutFallsBackWithoutOverwritingSavedValue() throws {
        let suite = "BoundScreenLayoutUnknown." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future", forKey: BoundAppearancePreferences.screenLayoutKey)
        let preferences = BoundAppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.screenLayout, .bound)
        XCTAssertEqual(defaults.string(forKey: BoundAppearancePreferences.screenLayoutKey), "future")
        preferences.resetScreenLayout()
        XCTAssertEqual(defaults.string(forKey: BoundAppearancePreferences.screenLayoutKey), "bound")
    }
    func testActualGBAIntegrationDistinguishesEngineAndUsesPinnedFallback() throws {
        let details = BoundEmulationDetails(packageName: "GBADeltaCore", packageIdentifier: "com.rileytestut.GBADeltaCore", packageVersion: nil)
        XCTAssertEqual(details.packageBuild, "Pinned source 869c34aeca9d")
        XCTAssertEqual(details.engineName, "VBA-M")
        XCTAssertEqual(details.engineRevision, "453fa0decf179360926fb417725a794aa496d6e3")
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("PrototypeConfiguration/dependency-pins.json"))
        let pins = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(details.packageRevision, pins["Cores/GBADeltaCore"])
        XCTAssertEqual(BoundEmulationDetails.deltaCoreRevision, pins["Cores/DeltaCore"])
        let exposed = BoundEmulationDetails(packageName: "Other", packageIdentifier: "other.core", packageVersion: "1.2.3")
        XCTAssertEqual(exposed.packageBuild, "1.2.3")
        XCTAssertNil(exposed.engineName)
        XCTAssertNil(exposed.packageRevision)
        XCTAssertEqual(BoundEmulationDetails(packageName: "Unknown", packageIdentifier: "other", packageVersion: nil).packageBuild, "Version not exposed by this package")
    }
}
