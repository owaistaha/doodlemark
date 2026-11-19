import XCTest

/// Step 4b: the real canvas screen, driven with synthesized finger touches in
/// landscape (the design's orientation). Screenshots are kept as attachments.
final class CanvasScreenUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSketchAndInkDrawOnTheirOwnLayers() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // Start from the shipped defaults whatever an earlier run left in
        // the simulator: Smooth my lines ON, Pencil only OFF.
        app.launchArguments += ["-resetProjects", "YES", "-hideCanvasTips", "YES", "-openNewLogo", "YES", "-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 0 lines.")
        keepScreenshot(app, "canvas-empty")

        // Sketch: a loose rocket outline.
        app.buttons["tool-sketch"].tap()
        for (from, to) in [((0.50, 0.18), (0.36, 0.55)), ((0.50, 0.18), (0.64, 0.55)), ((0.36, 0.56), (0.64, 0.57)),
                           ((0.36, 0.55), (0.26, 0.72)), ((0.64, 0.55), (0.74, 0.72))] {
            drag(stack, from, to)
        }
        try waitForValue(stack, "Sketch: 5 lines. Ink: 0 lines.")

        // Ink: clean lines on top.
        app.buttons["tool-ink"].tap()
        for (from, to) in [((0.50, 0.20), (0.37, 0.55)), ((0.50, 0.20), (0.63, 0.55)), ((0.37, 0.55), (0.63, 0.55)),
                           ((0.30, 0.82), (0.70, 0.82))] {
            drag(stack, from, to)
        }
        try waitForValue(stack, "Sketch: 5 lines. Ink: 4 lines.")

        // Shapes (placeholder): one-finger drags draw nothing anywhere.
        app.buttons["tool-shapes"].tap()
        drag(stack, (0.2, 0.3), (0.8, 0.35))
        sleep(1)
        XCTAssertEqual(stack.value as? String, "Sketch: 5 lines. Ink: 4 lines.")

        // Eraser works on the last drawing layer (Ink) and removes a whole line.
        app.buttons["tool-eraser"].tap()
        drag(stack, (0.45, 0.76), (0.55, 0.88))
        try waitForValue(stack, "Sketch: 5 lines. Ink: 3 lines.")

        app.buttons["tool-ink"].tap()
        drag(stack, (0.32, 0.82), (0.68, 0.82))
        try waitForValue(stack, "Sketch: 5 lines. Ink: 4 lines.")
        keepScreenshot(app, "canvas-ink")

        app.buttons["tool-sketch"].tap()
        keepScreenshot(app, "canvas-sketch-tool")
    }

    @MainActor
    func testPinchZoomsAndZoomPillFitsAgain() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // Start from the shipped defaults whatever an earlier run left in
        // the simulator: Smooth my lines ON, Pencil only OFF.
        app.launchArguments += ["-resetProjects", "YES", "-hideCanvasTips", "YES", "-openNewLogo", "YES", "-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
        let pill = app.buttons["zoomPill"]
        XCTAssertTrue(pill.label.hasPrefix("Zoom 100 percent"), pill.label)

        stack.pinch(withScale: 2, velocity: 1)
        sleep(1)
        XCTAssertFalse(pill.label.hasPrefix("Zoom 100 percent"), "pinch should zoom: \(pill.label)")
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 0 lines.", "a pinch must not draw")
        keepScreenshot(app, "canvas-zoomed")

        pill.tap()
        sleep(1)
        XCTAssertTrue(pill.label.hasPrefix("Zoom 100 percent"), pill.label)
    }

    // MARK: Step 4c: undo, redo, Mirror, Grid

    @MainActor
    func testUndoRedoButtonsAcrossLayerSwitches() throws {
        let (app, stack) = launchLandscape()
        let undo = app.buttons["undo"], redo = app.buttons["redo"]
        XCTAssertFalse(undo.isEnabled)

        drag(stack, (0.2, 0.2), (0.8, 0.2))                       // Ink
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")
        app.buttons["tool-sketch"].tap()
        drag(stack, (0.2, 0.5), (0.8, 0.5))                       // Sketch
        try waitForValue(stack, "Sketch: 1 line. Ink: 1 line.")
        app.buttons["tool-ink"].tap()
        drag(stack, (0.2, 0.8), (0.8, 0.8))                       // Ink
        try waitForValue(stack, "Sketch: 1 line. Ink: 2 lines.")

        undo.tap(); try waitForValue(stack, "Sketch: 1 line. Ink: 1 line.")
        undo.tap(); try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")   // Sketch, while Ink is active
        undo.tap(); try waitForValue(stack, "Sketch: 0 lines. Ink: 0 lines.")
        XCTAssertFalse(undo.isEnabled)
        redo.tap(); redo.tap(); redo.tap()
        try waitForValue(stack, "Sketch: 1 line. Ink: 2 lines.")
        XCTAssertFalse(redo.isEnabled)
    }

    @MainActor
    func testTwoFingerTapUndoesAndThreeFingerTapRedoes() throws {
        let (_, stack) = launchLandscape()
        drag(stack, (0.2, 0.3), (0.8, 0.3))
        drag(stack, (0.2, 0.6), (0.8, 0.6))
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")

        stack.twoFingerTap()
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")   // undo, and no dot left behind
        stack.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")   // redo, and no dot left behind

        // The taps work with the Sketch layer active too, without marking it.
        let app = XCUIApplication()
        app.buttons["tool-sketch"].tap()
        stack.twoFingerTap()
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")
    }

    @MainActor
    func testPinchNeverUndoes() throws {
        let (app, stack) = launchLandscape()
        drag(stack, (0.2, 0.3), (0.8, 0.3))
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")
        for scale in [1.8, 0.6, 2.2] {
            stack.pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
            sleep(1)
            XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 1 line.", "pinch \(scale) changed the drawing")
        }
        XCTAssertTrue(app.buttons["undo"].isEnabled)
        XCTAssertFalse(app.buttons["redo"].isEnabled, "nothing was undone")
    }

    /// Opt-in: `TEST_RUNNER_KEYBOARD_UI_TESTS=1 xcodebuild test … -only-testing:…/testCommandZUndoesAndShiftCommandZRedoes`
    /// on a freshly booted simulator. The headless simulator has no hardware
    /// keyboard attached (`ConnectHardwareKeyboard = 0`). `typeKey` key commands
    /// arrive on the first app launch after boot and are dropped on later
    /// launches, with the same code, so this can't run inside the full suite.
    @MainActor
    func testCommandZUndoesAndShiftCommandZRedoes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KEYBOARD_UI_TESTS"] == "1",
                          "Keyboard test: run alone on a freshly booted simulator (see comment).")
        let (app, stack) = launchLandscape()
        drag(stack, (0.2, 0.3), (0.8, 0.3))
        drag(stack, (0.2, 0.6), (0.8, 0.6))
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")
        app.typeKey("z", modifierFlags: .command)
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")
        sleep(1)
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 1 line.", "one ⌘Z must undo exactly one step")
        app.typeKey("z", modifierFlags: [.command, .shift])
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")
        sleep(1)
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 2 lines.")
    }

    @MainActor
    func testMirrorCopiesInTheSameUndoStepAndGridToggles() throws {
        let (app, stack) = launchLandscape()
        let mirror = app.buttons["mirror"], grid = app.buttons["grid"]
        XCTAssertEqual(mirror.value as? String, "Off")
        mirror.tap()
        XCTAssertEqual(mirror.value as? String, "On")
        XCTAssertTrue(app.descendants(matching: .any)["hintPill"].label.contains("Mirror is on"),
                      "the hint pill should say Mirror is on")

        // Half a rocket on the left; Mirror draws the right half.
        for (from, to) in [((0.50, 0.14), (0.40, 0.30)), ((0.40, 0.30), (0.38, 0.62)),
                           ((0.38, 0.62), (0.50, 0.62)), ((0.38, 0.55), (0.28, 0.72)), ((0.28, 0.72), (0.38, 0.66))] {
            drag(stack, from, to)
        }
        try waitForValue(stack, "Sketch: 0 lines. Ink: 10 lines.")
        app.buttons["undo"].tap()
        try waitForValue(stack, "Sketch: 0 lines. Ink: 8 lines.")    // one undo: a stroke and its mirror
        app.buttons["redo"].tap()
        try waitForValue(stack, "Sketch: 0 lines. Ink: 10 lines.")

        grid.tap()
        XCTAssertEqual(grid.value as? String, "On")
        keepScreenshot(app, "canvas-mirror-grid")
        grid.tap()
        XCTAssertEqual(grid.value as? String, "Off")
    }

    /// Step 5a: Try another recolors real, finger-drawn Ink lines (through
    /// PencilKit's own color storage), undo brings them back, and tap and
    /// hold opens the system color picker without making an undo step.
    @MainActor
    func testTryAnotherRecolorsDrawnLinesAndHoldOpensThePicker() throws {
        let (app, stack) = launchLandscape()
        let colors = app.descendants(matching: .any)["debugColors"]
        let starter = "palette #FF5A1F #1C1B22 #FFC93C"
        try waitForLabel(colors, "\(starter); ink ")

        drag(stack, (0.2, 0.3), (0.8, 0.3))                         // pen = color 2 (dark)
        app.descendants(matching: .any)["swatch-1"].tap()
        drag(stack, (0.2, 0.5), (0.8, 0.5))                         // pen = color 1
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")
        try waitForLabel(colors, "\(starter); ink #1C1B22 #FF5A1F")

        app.buttons["tryAnother"].tap()
        try waitForLabel(colors, "palette #1E88E5 #0D1B3E #4DD0E1; ink #0D1B3E #1E88E5")
        keepScreenshot(app, "palette-try-another")

        app.buttons["undo"].tap()
        try waitForLabel(colors, "\(starter); ink #1C1B22 #FF5A1F")
        XCTAssertTrue(app.buttons["redo"].isEnabled)

        app.descendants(matching: .any)["swatch-3"].press(forDuration: 1.0)
        let picker = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Color 3'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the system color picker opens")
        keepScreenshot(app, "palette-color-picker")
        stack.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()   // outside the popover
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        try waitForLabel(colors, "\(starter); ink #1C1B22 #FF5A1F")
        XCTAssertTrue(app.buttons["redo"].isEnabled, "closing the picker unchanged is no undo step")
        try waitForValue(stack, "Sketch: 0 lines. Ink: 2 lines.")   // and the tap outside drew nothing
    }

    /// Step 5b with synthesized touches: add, move (and snap back), resize by
    /// a corner handle, pinch and turn with two fingers on the shape, flip,
    /// delete, one undo per gesture, and two fingers off the shape still zoom.
    @MainActor
    func testAddMoveResizeTurnFlipAndDeleteAShape() throws {
        let (app, stack) = launchLandscape()
        let probe = app.descendants(matching: .any)["debugShapes"]
        let zoom = app.descendants(matching: .any)["zoomPill"]
        // Guard: the first UI test after the unit tests used to lose its very
        // first tap (step 6). With the launch wait fixed and the polling
        // probe gone it hasn't happened in 12 runs; the touch trace
        // (`-traceTouches YES`) showed the tap reaching the button every time.
        // If it ever comes back, the log says so and the tap is retried.
        for attempt in 0..<3 where !app.buttons["add-star"].exists {
            if attempt > 0 { print("LOST-FIRST-TAP| retrying the Shapes tap, attempt \(attempt)") }
            app.buttons["tool-shapes"].tap()
            _ = app.buttons["add-star"].waitForExistence(timeout: 2)
        }
        app.buttons["add-star"].tap()
        var star = try shape(probe)
        XCTAssertEqual(star.kind, "star")
        XCTAssertEqual(star.center, CGPoint(x: 512, y: 512))
        XCTAssertEqual(star.size, 320)
        XCTAssertEqual(star.fill, 2, "the current color")

        // One finger on the star moves it.
        drag(stack, (0.5, 0.5), (0.65, 0.5))
        let moved = try shape(probe)
        XCTAssertEqual(moved.center.x, 512 + 0.15 * 1024, accuracy: 12)
        app.buttons["undo"].tap()
        XCTAssertEqual(try shape(probe).center, star.center, "one undo for the whole drag")
        app.buttons["redo"].tap()
        XCTAssertEqual(try shape(probe).center, moved.center)

        // Dragged back close to the middle, it snaps to x = 512.
        drag(stack, (0.65, 0.5), (0.506, 0.5))
        star = try shape(probe)
        XCTAssertEqual(star.center.x, 512, "snapped")

        // The bottom-right corner handle (on the path bounds) resizes it.
        let r = star.size / 2
        let corner = (Double((star.center.x + r * cos(.pi / 10)) / 1024), Double((star.center.y + r * cos(.pi / 5)) / 1024))
        drag(stack, corner, (corner.0 + 0.08, corner.1 + 0.08))
        let resized = try shape(probe)
        XCTAssertGreaterThan(resized.size, star.size * 1.3)
        XCTAssertEqual(resized.center.x, star.center.x, accuracy: 1, "resizes around its centre")

        // Two fingers on the shape: the shape grows, the canvas doesn't zoom.
        stack.pinch(withScale: 0.7, velocity: -1)
        let pinched = try shape(probe)
        XCTAssertLessThan(pinched.size, resized.size * 0.9)
        XCTAssertEqual(zoom.label, "Zoom 100 percent. Tap to fit the canvas.", "the canvas stays put")
        stack.rotate(.pi / 4, withVelocity: 1)
        let turned = try shape(probe)
        XCTAssertNotEqual(turned.rotation, 0)
        XCTAssertEqual(turned.rotation % 15, 0, "15° steps")
        app.buttons["undo"].tap()
        XCTAssertEqual(try shape(probe).rotation, 0, "undo takes back the turn only")
        XCTAssertEqual(try shape(probe).size, pinched.size)

        app.buttons["flipUpsideDown"].tap()
        XCTAssertEqual(try shape(probe).rotation, 180)
        XCTAssertFalse(app.buttons["flipSideways"].isEnabled, "an upside-down star looks the same mirrored")

        app.buttons["deleteShape"].tap()
        XCTAssertEqual(try shape(probe).count, 0)
        app.buttons["undo"].tap()
        XCTAssertEqual(try shape(probe).count, 1)

        // Nothing picked now: two fingers zoom the canvas again.
        stack.pinch(withScale: 1.8, velocity: 1)
        XCTAssertNotEqual(zoom.label, "Zoom 100 percent. Tap to fit the canvas.")
        zoom.tap()
    }

    /// A small logo with two shapes for the report: a big circle in color 1
    /// behind a picked star in color 3.
    @MainActor
    func testShapesScreenshot() throws {
        let (app, stack) = launchLandscape()
        let probe = app.descendants(matching: .any)["debugShapes"]
        app.buttons["tool-shapes"].tap()
        app.descendants(matching: .any)["swatch-1"].tap()
        app.buttons["add-circle"].tap()
        // Grow the circle from its bottom-right handle (path bounds = its box).
        drag(stack, (0.65625, 0.65625), (0.76, 0.76))
        XCTAssertGreaterThan(try shape(probe).size, 450)
        app.descendants(matching: .any)["swatch-3"].tap()                 // refills the circle
        XCTAssertEqual(try shape(probe).fill, 3)
        app.descendants(matching: .any)["swatch-2"].tap()                 // and back: color 2 ink-dark
        app.descendants(matching: .any)["swatch-1"].tap()
        stack.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()   // pick nothing
        XCTAssertEqual(try shape(probe).count, 1)
        app.descendants(matching: .any)["swatch-3"].tap()
        app.buttons["add-star"].tap()
        XCTAssertEqual(try shape(probe).fill, 3)
        keepScreenshot(app, "shapes-picked")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)            // the rest of the panel
        keepScreenshot(app, "shapes-panel")
    }

    /// Step 5c with the real keyboard: type a name (one undo step for the
    /// whole session), a character the font can't draw (friendly note, not
    /// typed), the font picker, a finger drag on the text, letter spacing and
    /// ALL CAPS. Screenshot with the keyboard covering the bottom of the screen.
    @MainActor
    func testTypeALogoNamePickAFontAndMoveIt() throws {
        let (app, stack) = launchLandscape()
        let probe = app.descendants(matching: .any)["debugText"]
        app.buttons["tool-text"].tap()
        XCTAssertEqual(probe.label, "no text")
        let field = app.textFields["textField"]
        field.tap()
        field.typeText("Pizza Rocket")
        try waitForLabel(probe, "text Pizza Rocket; LilitaOne 120 0° fill 2 tracking 0 caps off; at 512 512")
        keepScreenshot(app, "text-keyboard-up")

        field.typeText("★")
        let message = app.staticTexts["textMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertEqual(message.label, "This font can't draw \u{201C}★\u{201D}.")
        XCTAssertTrue(probe.label.hasPrefix("text Pizza Rocket;"), "not typed")
        XCTAssertEqual(field.value as? String, "Pizza Rocket", "and not left in the field")
        sleep(1)                                         // the panel scrolls the name block up
        let keys = app.keyboards.firstMatch
        XCTAssertTrue(keys.exists, "the on-screen keyboard is up")
        XCTAssertLessThan(message.frame.maxY, keys.frame.minY, "the note is above the keyboard, not behind it")
        XCTAssertLessThan(field.frame.maxY, keys.frame.minY)
        keepScreenshot(app, "text-blocked-note")

        toolbarButton(app, "undo").tap()
        try waitForLabel(probe, "no text")              // twelve letters, one step
        XCTAssertEqual(field.value as? String, "Your logo name", "the field follows (placeholder)")
        toolbarButton(app, "redo").tap()
        try waitForLabel(probe, "text Pizza Rocket; LilitaOne 120 0° fill 2 tracking 0 caps off; at 512 512")
        hideKeyboard(app)

        app.buttons["font-Pacifico-Regular"].tap()
        XCTAssertTrue(probe.label.contains("Pacifico-Regular 120"))
        XCTAssertTrue(app.buttons["font-Pacifico-Regular"].isSelected)

        // One finger on the text moves it; one undo puts it back.
        drag(stack, (0.5, 0.5), (0.6, 0.62))
        let at = try textCenter(probe)
        XCTAssertEqual(at.x, 512 + 0.1 * 1024, accuracy: 12)
        XCTAssertEqual(at.y, 512 + 0.12 * 1024, accuracy: 12)
        toolbarButton(app, "undo").tap()
        XCTAssertEqual(try textCenter(probe), CGPoint(x: 512, y: 512))

        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        app.sliders["Letter spacing"].adjust(toNormalizedSliderPosition: 0.4)
        sleep(1)
        XCTAssertFalse(probe.label.contains("tracking 0 "), probe.label)
        app.descendants(matching: .any)["allCaps"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(probe.label.contains("caps on"), probe.label)
        XCTAssertTrue(probe.label.hasPrefix("text Pizza Rocket;"), "what was typed is kept")
    }

    /// The report's text shot: a tangerine circle behind "Pizza Rocket" in
    /// Sniglet, letter-spaced, picked, with the font picker in the panel.
    @MainActor
    func testTextScreenshot() throws {
        let (app, stack) = launchLandscape()
        let probe = app.descendants(matching: .any)["debugText"]
        app.buttons["tool-shapes"].tap()
        app.descendants(matching: .any)["swatch-1"].tap()
        app.buttons["add-circle"].tap()
        drag(stack, (0.65625, 0.65625), (0.78, 0.78))
        app.buttons["tool-text"].tap()
        app.descendants(matching: .any)["swatch-2"].tap()
        app.buttons["font-Sniglet-ExtraBold"].tap()
        let field = app.textFields["textField"]
        field.tap()
        field.typeText("Pizza Rocket")
        try waitForLabel(probe, "text Pizza Rocket; Sniglet-ExtraBold 120 0° fill 2 tracking 0 caps off; at 512 512")
        hideKeyboard(app)
        keepScreenshot(app, "text-picked")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        app.sliders["Letter spacing"].adjust(toNormalizedSliderPosition: 0.25)
        keepScreenshot(app, "text-panel")
    }

    // MARK: Helpers

    /// The text's centre from `debugText` ("…; at 512 512").
    @MainActor
    private func textCenter(_ probe: XCUIElement) throws -> CGPoint {
        sleep(1)
        let f = try XCTUnwrap(probe.label.components(separatedBy: "; at ").last?.components(separatedBy: " "))
        return CGPoint(x: Double(f[0]) ?? -1, y: Double(f[1]) ?? -1)
    }

    /// The canvas toolbar's button, not the keyboard shortcut bar's Undo/Redo
    /// (both match while the keyboard is up).
    @MainActor
    private func toolbarButton(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let keyboard = app.keyboards.firstMatch
        let all = app.buttons.matching(identifier: id).allElementsBoundByIndex
        guard keyboard.exists else { return all.first ?? app.buttons[id] }
        let shortcutsTop = keyboard.frame.minY - 80          // the bar floats just above the keys
        return all.first { $0.frame.maxY < shortcutsTop } ?? app.buttons[id]
    }

    /// The iPad keyboard's own hide key (what a person taps).
    @MainActor
    private func hideKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let hide = app.keyboards.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'keyboard'")).firstMatch
        if hide.exists { hide.tap() } else { app.keyboards.buttons["Done"].firstMatch.tap() }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }


    private struct ShapeState {
        var count: Int
        var kind = ""
        var center = CGPoint.zero
        var size: CGFloat = 0
        var rotation = 0
        var fill = 0
    }

    /// Reads `debugShapes`: "1 shapes; selected star 512 512 320 0° fill 2".
    @MainActor
    private func shape(_ probe: XCUIElement) throws -> ShapeState {
        sleep(1)    // let the last gesture's update land
        let label = probe.label
        let parts = label.components(separatedBy: "; ")
        var state = ShapeState(count: Int(parts[0].components(separatedBy: " ")[0]) ?? -1)
        if let picked = parts.first(where: { $0.hasPrefix("selected ") }) {
            let f = picked.components(separatedBy: " ")
            state.kind = f[1]
            state.center = CGPoint(x: Double(f[2]) ?? -1, y: Double(f[3]) ?? -1)
            state.size = CGFloat(Double(f[4]) ?? -1)
            state.rotation = Int(f[5].replacingOccurrences(of: "°", with: "")) ?? -1
            state.fill = Int(f[7]) ?? -1
        } else if state.count > 0, label.contains("selected") {
            XCTFail("can't read \(label)")
        }
        return state
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 5) != .completed {
            XCTFail("expected label \(label), got \(element.exists ? element.label : "no element")")
            throw XCTSkip("stopping")
        }
    }

    @MainActor
    private func launchLandscape() -> (XCUIApplication, XCUIElement) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // Start from the shipped defaults whatever an earlier run left in
        // the simulator: Smooth my lines ON, Pencil only OFF.
        app.launchArguments += ["-resetProjects", "YES", "-hideCanvasTips", "YES", "-openNewLogo", "YES", "-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
        // Let the turn to landscape finish: a tap during it can land on the
        // portrait position of a button (seen once on a first launch).
        // (A predicate on "frame.size.width" never matches: XCUIElement's
        // frame isn't key-value readable that way, so it waited the full 5 s.)
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height, Date() < deadline { usleep(100_000) }
        sleep(1)
        return (app, stack)
    }

    @MainActor
    private func drag(_ element: XCUIElement, _ from: (Double, Double), _ to: (Double, Double)) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 5) != .completed {
            XCTFail("expected \(value), got \(element.value ?? "nil")")
            throw XCTSkip("stopping")
        }
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        sleep(1)   // let button press animations finish
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
