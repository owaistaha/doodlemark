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
        app.launchArguments += ["-smoothLines", "YES", "-pencilOnly", "NO"]
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
        app.launchArguments += ["-smoothLines", "YES", "-pencilOnly", "NO"]
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

    // MARK: Helpers

    @MainActor
    private func launchLandscape() -> (XCUIApplication, XCUIElement) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // Start from the shipped defaults whatever an earlier run left in
        // the simulator: Smooth my lines ON, Pencil only OFF.
        app.launchArguments += ["-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
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
