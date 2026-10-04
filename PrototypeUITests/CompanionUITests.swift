import XCTest

final class CompanionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func openGame(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Legacy layout regression cases explicitly opt into Bound; the native
        // layout case removes this helper-only marker and exercises persistence.
        app.launchArguments = arguments.filter { $0 != "--bound-ui-native-layout" }
        if !arguments.contains("--bound-ui-native-layout") {
            app.launchArguments.append("--bound-ui-screen-layout-bound")
        }
        app.launch()
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        let cell = app.collectionViews.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 20))
        cell.tap()
        XCTAssertTrue(app.segmentedControls["bound.panel-toggle"].waitForExistence(timeout: 15))
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // Short Form drags avoid jumping past a lazily materialized row in landscape.
    private func scrollToSetting(_ target: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews.firstMatch
        for _ in 0..<40 {
            if target.exists && target.isHittable { return }
            let scrollDown = target.exists && target.frame.midY < form.frame.midY
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.35 : 0.80))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.65 : 0.50))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.isHittable)
    }

    private func waitForFrame(_ element: XCUIElement, _ predicate: @escaping (CGRect) -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && predicate(element.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }

    func testOfflineFriendPixelsFitBothLayouts() throws {
        let app = openGame(arguments: ["--bound-ui-friend-fixture"])
        app.segmentedControls["bound.panel-toggle"].buttons["Friend"].tap()
        let friend = element("bound.friend-screen", in: app)
        let game = element("bound.game-screen", in: app)
        XCTAssertTrue(friend.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Connect a friend"].exists)
        XCTAssertEqual(friend.frame.width / friend.frame.height, 1.5, accuracy: 0.015)
        XCTAssertEqual(game.frame.width / game.frame.height, 1.5, accuracy: 0.015)
        XCTAssertEqual(friend.frame.width, game.frame.width, accuracy: 2)
        screenshot("Bound-portrait-offline-friend-pixels")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { $0.height > app.frame.height * 0.8 }
        XCTAssertEqual(friend.frame.width / friend.frame.height, 1.5, accuracy: 0.015)
        screenshot("Bound-landscape-offline-friend-pixels")
    }

    func testDualScreenPortraitAndLandscapePictureInPicture() throws {
        let app = openGame()
        app.segmentedControls["bound.panel-toggle"].buttons["Friend"].tap()
        let friend = element("bound.friend-screen", in: app)
        let game = element("bound.game-screen", in: app)
        XCTAssertTrue(friend.waitForExistence(timeout: 5))
        XCTAssertTrue(game.waitForExistence(timeout: 5))
        waitForFrame(friend) { $0.width > 100 && $0.maxY <= game.frame.minY + 2 }
        XCTAssertTrue(app.staticTexts["Connect a friend"].exists)
        screenshot("Bound-portrait-dual-screen-no-friend")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { $0.width > $0.height && $0.height > app.frame.height * 0.8 }
        XCTAssertGreaterThanOrEqual(friend.frame.minX, app.frame.minX)
        XCTAssertGreaterThanOrEqual(friend.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(friend.frame.maxX, app.frame.maxX + 1)
        XCTAssertLessThanOrEqual(friend.frame.maxY, app.frame.maxY + 1)
        XCTAssertLessThan(friend.frame.width, game.frame.width * 0.65)
        screenshot("Bound-landscape-full-height-game-and-pip")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(friend.waitForExistence(timeout: 5))
        XCTAssertTrue(game.exists)
        XCUIDevice.shared.orientation = .portrait
        waitForFrame(friend) { $0.maxY <= game.frame.minY + 2 }
        screenshot("Bound-portrait-after-rotation-and-foreground")
    }

    func testPictureInPictureGesturesAndTransparencyPersist() throws {
        let app = openGame(arguments: ["--bound-ui-reset-layout"])
        app.segmentedControls["bound.panel-toggle"].buttons["Friend"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let friend = element("bound.friend-screen", in: app)
        waitForFrame(friend) { $0.width > 100 && app.frame.width > app.frame.height }
        let initial = friend.frame
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: initial.midX > app.frame.midX ? 0.30 : 0.70, dy: 0.35))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.15, thenDragTo: destination)
        waitForFrame(friend) { abs($0.midX - initial.midX) > 30 || abs($0.midY - initial.midY) > 30 }
        screenshot("Bound-landscape-pip-moved")
        let game = element("bound.game-screen", in: app)
        game.pinch(withScale: 0.5, velocity: -1)
        let movedWidth = friend.frame.width
        game.pinch(withScale: 1.2, velocity: 1)
        waitForFrame(friend) { $0.width > movedWidth + 5 }
        screenshot("Bound-landscape-pip-resized")
        app.buttons["bound.layout-settings"].tap()
        let transparency = app.sliders["bound.friend-transparency"]
        scrollToSetting(transparency, in: app)
        XCTAssertTrue(transparency.waitForExistence(timeout: 5))
        transparency.adjust(toNormalizedSliderPosition: 0.45)
        let savedValue = transparency.value as? String
        XCTAssertNotNil(savedValue)
        screenshot("Bound-friend-transparency-setting")
        app.buttons["Done"].firstMatch.tap()
        let savedFrame = friend.frame
        app.terminate()
        _ = openGame()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(friend) { app.frame.width > app.frame.height && abs($0.width - savedFrame.width) < 3 }
        XCTAssertEqual(friend.frame.midX, savedFrame.midX, accuracy: 3)
        XCTAssertEqual(friend.frame.midY, savedFrame.midY, accuracy: 3)
        app.buttons["bound.layout-settings"].tap()
        scrollToSetting(transparency, in: app)
        XCTAssertTrue(transparency.waitForExistence(timeout: 5))
        XCTAssertEqual(transparency.value as? String, savedValue)
        // Restore visibility without resetting saved movement or scale.
        transparency.adjust(toNormalizedSliderPosition: 0)
        app.buttons["Done"].firstMatch.tap()
        XCUIDevice.shared.orientation = .portrait
        screenshot("Bound-portrait-after-pip-customization")
    }

    func testControlPlacementSaveResetAndOrientationIsolation() throws {
        let app = openGame()
        func openPlacement() {
            app.buttons["bound.layout-settings"].tap()
            let placement = app.buttons["bound.button-placement"]
            XCTAssertTrue(placement.waitForExistence(timeout: 5))
            if !placement.isHittable { app.swipeUp() }
            placement.tap()
            XCTAssertTrue(app.otherElements["controls.editor.preview"].waitForExistence(timeout: 5))
        }
        func tapEditorButton(_ identifier: String) {
            let button = app.buttons[identifier]
            for _ in 0..<5 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable)
            button.tap()
        }
        openPlacement()
        tapEditorButton("controls.editor.reset-all")
        app.buttons["Save"].tap()
        openPlacement()
        let size = app.sliders["controls.editor.size"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Size: 100%"].exists)
        size.adjust(toNormalizedSliderPosition: 0.8)
        let customSize = size.value as? String
        tapEditorButton("controls.editor.nudge.→")
        screenshot("Bound-portrait-custom-control-placement")
        app.buttons["Save"].tap()
        let game = element("bound.game-screen", in: app)
        XCTAssertTrue(game.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(game.frame.height, 100)
        XCTAssertEqual(game.frame.width / game.frame.height, 1.5, accuracy: 0.015)
        screenshot("Bound-portrait-gameplay-with-custom-controls")
        app.terminate()
        _ = openGame()
        openPlacement()
        XCTAssertEqual(size.value as? String, customSize)
        app.buttons["Cancel"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        openPlacement()
        XCTAssertTrue(app.staticTexts["Size: 100%"].exists)
        screenshot("Bound-landscape-default-control-placement")
        app.buttons["Cancel"].tap()
        XCUIDevice.shared.orientation = .portrait
        openPlacement()
        tapEditorButton("controls.editor.reset-all")
        app.buttons["Save"].tap()
        openPlacement()
        XCTAssertTrue(app.staticTexts["Size: 100%"].exists)
        app.buttons["Cancel"].tap()
    }

    func testThemeAndHapticPreferencesPersistAndReset() throws {
        let app = openGame(arguments: ["--bound-ui-friend-fixture"])
        let toggle = app.segmentedControls["bound.panel-toggle"]
        toggle.buttons["Friend"].tap()
        let friend = element("bound.friend-screen", in: app)
        let game = element("bound.game-screen", in: app)
        func settings() {
            app.buttons["bound.layout-settings"].tap()
            XCTAssertTrue(element("bound.theme", in: app).waitForExistence(timeout: 5))
        }
        func scrollTo(_ target: XCUIElement) {
            for _ in 0..<12 where !target.exists || !target.isHittable { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(target.isHittable)
        }
        func resetAppearance() {
            let reset = app.buttons["bound.reset-appearance"]
            scrollTo(reset)
            reset.tap()
            let theme = element("bound.theme", in: app)
            for _ in 0..<12 where !theme.exists || !theme.isHittable { app.collectionViews.firstMatch.swipeDown() }
            XCTAssertTrue(theme.isHittable)
        }
        settings()
        resetAppearance()
        let buttonHaptics = app.switches["bound.button-haptics"]
        let stickHaptics = app.switches["bound.stick-haptics"]
        XCTAssertEqual(buttonHaptics.value as? String, "1")
        XCTAssertEqual(stickHaptics.value as? String, "1")
        app.buttons["Done"].firstMatch.tap()
        screenshot("Bound-Delta-default-theme-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { $0.height > app.frame.height * 0.8 }
        screenshot("Bound-Delta-default-theme-landscape")
        XCUIDevice.shared.orientation = .portrait
        settings()
        element("bound.theme", in: app).tap()
        let minimal = app.buttons["Minimal"].firstMatch
        XCTAssertTrue(minimal.waitForExistence(timeout: 5))
        minimal.tap()
        scrollTo(buttonHaptics)
        buttonHaptics.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        scrollTo(stickHaptics)
        stickHaptics.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(buttonHaptics.value as? String, "0")
        XCTAssertEqual(stickHaptics.value as? String, "0")
        screenshot("Bound-Minimal-theme-haptic-settings")
        app.buttons["Done"].firstMatch.tap()
        waitForFrame(friend) { $0.maxY <= game.frame.minY + 2 }
        XCTAssertEqual(game.frame.width / game.frame.height, 1.5, accuracy: 0.015)
        screenshot("Bound-Minimal-theme-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { $0.height > app.frame.height * 0.8 }
        XCTAssertEqual(friend.frame.width / friend.frame.height, 1.5, accuracy: 0.015)
        screenshot("Bound-Minimal-theme-landscape")
        toggle.buttons["Types"].tap()
        XCTAssertTrue(app.scrollViews["bound.type-chart"].waitForExistence(timeout: 5))
        toggle.buttons["Notes"].tap()
        XCTAssertTrue(app.textViews["bound.notes-editor"].waitForExistence(timeout: 5))
        toggle.buttons["Friend"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        app.terminate()
        _ = openGame(arguments: ["--bound-ui-friend-fixture"])
        XCUIDevice.shared.orientation = .portrait
        waitForFrame(game) { $0.width < app.frame.height && app.frame.height > app.frame.width }
        settings()
        XCTAssertEqual(buttonHaptics.value as? String, "0")
        XCTAssertEqual(stickHaptics.value as? String, "0")
        let persistedTheme = element("bound.theme", in: app)
        XCTAssertTrue(persistedTheme.label.contains("Minimal") || (persistedTheme.value as? String)?.contains("Minimal") == true)
        resetAppearance()
        XCTAssertEqual(buttonHaptics.value as? String, "1")
        XCTAssertEqual(stickHaptics.value as? String, "1")
        screenshot("Bound-reset-appearance-settings")
        app.buttons["Done"].firstMatch.tap()
    }

    func testNativeAndBoundScreenLayoutChoicePersistsAndReportsBackend() throws {
        let nativeArguments = ["--bound-ui-native-layout", "--bound-ui-friend-fixture"]
        let app = openGame(arguments: nativeArguments + ["--bound-ui-reset-screen-layout"])
        let game = element("bound.game-screen", in: app)
        let friend = element("bound.friend-screen", in: app)
        XCTAssertTrue(game.waitForExistence(timeout: 5))
        func settings() {
            app.buttons["bound.layout-settings"].tap()
            XCTAssertTrue(element("bound.screen-layout", in: app).waitForExistence(timeout: 5))
        }
        func scrollTo(_ target: XCUIElement) {
            for _ in 0..<12 where !target.exists || !target.isHittable { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(target.isHittable)
        }
        func assertSelection(_ expected: String) {
            let picker = element("bound.screen-layout", in: app)
            XCTAssertTrue(picker.label.contains(expected) || (picker.value as? String)?.contains(expected) == true)
        }
        func chooseLayout(_ name: String) {
            element("bound.screen-layout", in: app).tap()
            let choice = app.buttons[name].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            assertSelection(name)
            app.buttons["Done"].firstMatch.tap()
        }
        func matches(_ frame: CGRect, _ expected: CGRect) -> Bool {
            abs(frame.minX - expected.minX) < 3 && abs(frame.minY - expected.minY) < 3 &&
            abs(frame.width - expected.width) < 3 && abs(frame.height - expected.height) < 3
        }
        settings()
        assertSelection("Delta Default")
        app.buttons["Done"].firstMatch.tap()
        waitForFrame(game) { $0.width > 100 && $0.height > 100 && app.frame.height > app.frame.width }
        let nativePortrait = game.frame
        screenshot("Bound-native-Delta-layout-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { app.frame.width > app.frame.height && $0.width > $0.height }
        let nativeLandscape = game.frame
        screenshot("Bound-native-Delta-layout-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForFrame(game) { matches($0, nativePortrait) }
        settings()
        chooseLayout("Bound")
        waitForFrame(game) { !matches($0, nativePortrait) && friend.frame.maxY <= $0.minY + 2 }
        let boundPortrait = game.frame
        screenshot("Bound-selected-dual-screen-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { app.frame.width > app.frame.height && $0.height > app.frame.height * 0.8 }
        screenshot("Bound-selected-full-height-landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        _ = openGame(arguments: nativeArguments)
        waitForFrame(game) { matches($0, boundPortrait) }
        settings()
        assertSelection("Bound")
        // Appearance reset must leave the independent screen arrangement alone.
        let resetAppearance = app.buttons["bound.reset-appearance"]
        scrollTo(resetAppearance)
        resetAppearance.tap()
        let picker = element("bound.screen-layout", in: app)
        for _ in 0..<12 where !picker.exists || !picker.isHittable { app.collectionViews.firstMatch.swipeDown() }
        assertSelection("Bound")
        func assertBackend(_ identifier: String, contains value: String) {
            let row = element(identifier, in: app)
            scrollTo(row)
            let content = row.label + " " + ((row.value as? String) ?? "") + " " + row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            XCTAssertTrue(content.contains(value), "Backend row \(identifier) must contain \(value), got \(content)")
        }
        assertBackend("bound.emulation-package", contains: "GBADeltaCore")
        assertBackend("bound.emulation-package-build", contains: "869c34aeca9d")
        assertBackend("bound.emulation-engine", contains: "VBA-M")
        assertBackend("bound.emulation-engine-build", contains: "453fa0decf17")
        screenshot("Bound-active-GBA-backend-details")
        for _ in 0..<12 where !picker.exists || !picker.isHittable { app.collectionViews.firstMatch.swipeDown() }
        chooseLayout("Delta Default")
        waitForFrame(game) { matches($0, nativePortrait) }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForFrame(game) { matches($0, nativeLandscape) }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        _ = openGame(arguments: nativeArguments)
        waitForFrame(game) { matches($0, nativePortrait) }
        settings()
        assertSelection("Delta Default")
        chooseLayout("Bound")
        waitForFrame(game) { matches($0, boundPortrait) }
        settings()
        let reset = app.buttons["bound.reset-screen-layout"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        assertSelection("Delta Default")
        app.buttons["Done"].firstMatch.tap()
        waitForFrame(game) { matches($0, nativePortrait) }
        screenshot("Bound-reset-native-Delta-layout-portrait")
        // Native Delta's screen geometry must survive companion gestures and
        // keyboard editing; only the overlay is allowed to move or resize.
        game.pinch(withScale: 0.5, velocity: -1)
        let compactFriendWidth = friend.frame.width
        game.pinch(withScale: 1.2, velocity: 1)
        waitForFrame(friend) { $0.width > compactFriendWidth + 5 }
        XCTAssertTrue(matches(game.frame, nativePortrait))
        screenshot("Bound-native-portrait-pip-resized")
        let toggle = app.segmentedControls["bound.panel-toggle"]
        toggle.buttons["Notes"].tap()
        let editor = app.textViews["bound.notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Native layout QA note")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(matches(game.frame, nativePortrait))
        screenshot("Bound-native-portrait-notes-keyboard")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed)
        XCTAssertTrue(matches(game.frame, nativePortrait))
        toggle.buttons["Types"].tap()
        XCTAssertTrue(app.scrollViews["bound.type-chart"].waitForExistence(timeout: 5))
        XCTAssertTrue(matches(game.frame, nativePortrait))
        screenshot("Bound-native-portrait-type-chart")
        toggle.buttons["Friend"].tap()
        XCTAssertTrue(friend.waitForExistence(timeout: 5))
        XCTAssertTrue(matches(game.frame, nativePortrait))
    }

    func testPanelsAndNotesPersist() throws {
        let app = openGame()
        let toggle = app.segmentedControls["bound.panel-toggle"]
        toggle.buttons["Notes"].tap()
        let editor = app.textViews["bound.notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("QA companion note")
        screenshot("Bound-portrait-notes-keyboard")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        screenshot("Bound-landscape-notes-keyboard")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" after foreground")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        toggle.buttons["Types"].tap()
        XCTAssertTrue(app.scrollViews["bound.type-chart"].waitForExistence(timeout: 5))
        screenshot("Bound-landscape-type-chart")
        toggle.buttons["Friend"].tap()
        app.buttons["bound.friends"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign in"].isEnabled)
        app.buttons["Done"].firstMatch.tap()
        toggle.buttons["Notes"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("QA companion note") == true)
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        _ = openGame()
        toggle.buttons["Notes"].tap()
        XCTAssertTrue((editor.value as? String)?.contains("QA companion note") == true)
        screenshot("Bound-portrait-notes-restored")
    }
}

/// Requires the original generated fixture in Documents/PickerImportQA.
/// Staging is documented in PrototypeTools/verify.sh; no personal ROM is read.
final class FileImportUITests: XCTestCase {
    func testActualFilesPickerCancelRetryAndImport() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 10))
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20))
        app.buttons["Browse"].firstMatch.tap()
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 15)); local.tap()
        let bound = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Bound 2")).firstMatch
        XCTAssertTrue(bound.waitForExistence(timeout: 15)); bound.tap()
        let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "PickerImportQA")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "BoundPickerDiagnostic")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        XCTAssertTrue(file.isEnabled)
        file.tap()
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 20))
        // Game cells expose their title as a child StaticText, not a cell label.
        let search = app.searchFields["Search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("BoundPickerDiagnostic")
        let imported = app.collectionViews.cells.containing(.staticText, identifier: "BoundPickerDiagnostic").firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 20))
        imported.tap()
        XCTAssertTrue(app.segmentedControls["bound.panel-toggle"].waitForExistence(timeout: 15))
    }
}

final class ReleaseSmokeUITests: XCTestCase {
    func testReleaseLibrarySettingsAndPlaybackHaveNoDevelopmentUI() throws {
        #if DEBUG
        throw XCTSkip("Run this smoke case with -configuration Release.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Close"].exists, "No upstream release-note onboarding")
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["Experimental Features"].exists)
        XCTAssertFalse(app.staticTexts["Delta Sync"].exists)
        XCTAssertFalse(app.staticTexts["Patreon"].exists)
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()
        // A generated game is imported by the fixture setup, never a personal ROM.
        let cell = app.collectionViews.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 20)); cell.tap()
        XCTAssertTrue(app.segmentedControls["bound.panel-toggle"].waitForExistence(timeout: 15))
        app.buttons["bound.layout-settings"].tap()
        let about = app.staticTexts["About Bound 2"].firstMatch
        for _ in 0..<6 {
            if about.exists && about.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Build entry"].exists)
        XCTAssertFalse(app.staticTexts["Engine source"].exists)
        XCTAssertFalse(app.staticTexts["Package identifier"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "private testing prototype")).firstMatch.exists)
        app.buttons["Done"].firstMatch.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.segmentedControls["bound.panel-toggle"].exists)
        app.buttons["Notes"].firstMatch.tap()
        XCTAssertTrue(app.textViews["bound.notes-editor"].waitForExistence(timeout: 10))
        app.buttons["Types"].firstMatch.tap()
        XCTAssertTrue(app.scrollViews["bound.type-chart"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
}
