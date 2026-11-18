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

    // MARK: Helpers

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
