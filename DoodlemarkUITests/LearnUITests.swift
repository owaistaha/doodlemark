import XCTest

/// Step 8b with real touches: the Learn tab, the lesson player traced with
/// synthesized one-finger strokes along the targets, the complete screen,
/// "Make it yours", and the result in My logos.
final class LearnUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The whole rocket, every stroke traced along its target: 15 stars,
    /// Make it yours opens the canvas with the strokes, and back in the
    /// gallery it's a project.
    @MainActor
    func testRocketLessonStartToFinishThenMakeItYours() throws {
        let app = launch(["-resetProjects", "YES", "-resetLearnProgress", "YES"])
        app.buttons["tab-learn"].tap()
        let rocket = app.buttons["lesson-rocket"]
        XCTAssertTrue(rocket.waitForExistence(timeout: 5))
        XCTAssertTrue(rocket.label.hasSuffix("New"), rocket.label)
        XCTAssertEqual(app.descendants(matching: .any)["starTotal"].label, "0 stars earned in lessons")
        rocket.tap()

        // Step 1: the badge. A shape step: Place it.
        XCTAssertTrue(app.buttons["placeShape"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["stepProgress"].label, "Step 1 of 5")
        keepScreenshot("lesson-place-it")
        app.buttons["placeShape"].tap()

        // Steps 2–5: trace each target.
        let stack = app.descendants(matching: .any)["canvasStack"]
        let target = app.descendants(matching: .any)["debugLessonTarget"]
        for step in 2...5 {
            try waitFor(app.descendants(matching: .any)["stepProgress"], label: "Step \(step) of 5")
            let points = TouchSynthesis.parse(target.label)
            XCTAssertGreaterThanOrEqual(points.count, 2, "step \(step) target")
            try TouchSynthesis.stroke(TouchSynthesis.screenPoints(points, canvasFrame: stack.frame), in: app)
            try waitFor(app.descendants(matching: .any)["resultStars"], label: "3 of 3 stars")
            XCTAssertEqual(app.staticTexts["resultTitle"].label, "Spot on")
            if step == 4 { keepScreenshot("lesson-result-fins") }
            app.buttons["nextStep"].tap()
        }

        try waitFor(app.descendants(matching: .any)["lessonTotal"], label: "15 of 15 stars")
        for (index, name) in ["The badge", "The body", "The base", "The fins", "The window"].enumerated() {
            XCTAssertEqual(app.descendants(matching: .any)["stepStars-\(index + 1)"].label, "\(name), 3 of 3 stars")
        }
        XCTAssertEqual(app.buttons["tryAgain"].label, "Play again", "15 of 15: nothing more to try for")
        XCTAssertEqual(app.buttons["nextLesson"].label, "Next: Lightning shield")
        keepScreenshot("lesson-complete")

        // Make it yours: a new project on the canvas, with the strokes.
        app.buttons["makeItYours"].tap()
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 8 lines.", "4 traced steps, each mirrored")
        XCTAssertTrue(app.descendants(matching: .any)["debugShapes"].label.hasPrefix("1 shapes"))
        XCTAssertEqual(app.buttons["mirror"].value as? String, "On")
        XCTAssertTrue(app.buttons["projectTitle"].label.hasPrefix("Rocket in 5 strokes, Saved"), app.buttons["projectTitle"].label)
        XCTAssertTrue(app.descendants(matching: .any)["debugColors"].label.hasPrefix("palette #FF5A1F #1C1B22 #FFC93C"))
        keepScreenshot("make-it-yours-canvas")

        // Back: it's in My logos.
        app.buttons["back"].tap()
        let card = app.buttons["projectCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.hasPrefix("Rocket in 5 strokes, Edited"), card.label)
        keepScreenshot("gallery-after-make-it-yours")

        // And the Learn tab has the best score.
        app.buttons["tab-learn"].tap()
        XCTAssertTrue(app.buttons["lesson-rocket"].label.contains("Best: 15 of 15 stars"), app.buttons["lesson-rocket"].label)
        XCTAssertEqual(app.descendants(matching: .any)["starTotal"].label, "15 stars earned in lessons")
    }

    /// A lesson left at step 4 picks up there; an off-the-line stroke gets
    /// fewer stars and Redo; leaving keeps the place.
    @MainActor
    func testResumeAResultAndRedo() throws {
        let app = launch(["-seedLearnProgress", "YES"])
        app.buttons["tab-learn"].tap()
        let rocket = app.buttons["lesson-rocket"]
        XCTAssertTrue(rocket.waitForExistence(timeout: 5))
        XCTAssertTrue(rocket.label.contains("Continue, step 4 of 5"), rocket.label)
        XCTAssertTrue(app.buttons["lesson-bolt-shield"].label.contains("Best: 11 of 12 stars"))
        XCTAssertEqual(app.descendants(matching: .any)["starTotal"].label, "20 stars earned in lessons")
        keepScreenshot("learn-tab")
        rocket.tap()

        try waitFor(app.descendants(matching: .any)["stepProgress"], label: "Step 4 of 5")
        XCTAssertEqual(app.staticTexts["stepTip"].label, "Give it fins so it looks like it's flying")
        keepScreenshot("lesson-fins")

        // The fins, drawn 24 canvas points too low: 2 stars, "So close".
        let stack = app.descendants(matching: .any)["canvasStack"]
        let points = TouchSynthesis.parse(app.descendants(matching: .any)["debugLessonTarget"].label)
        try TouchSynthesis.stroke(TouchSynthesis.screenPoints(points.map { CGPoint(x: $0.x, y: $0.y + 24) },
                                                              canvasFrame: stack.frame), in: app)
        try waitFor(app.descendants(matching: .any)["resultStars"], label: "2 of 3 stars")
        XCTAssertEqual(app.staticTexts["resultTitle"].label, "So close")
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 6 lines.", "body, base and fins, each mirrored")
        keepScreenshot("lesson-result-two-stars")

        app.buttons["redoStroke"].tap()
        XCTAssertTrue(app.buttons["redoStroke"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 4 lines.")

        // Way off: 0 stars, said kindly.
        try TouchSynthesis.stroke(TouchSynthesis.screenPoints([CGPoint(x: 80, y: 900), CGPoint(x: 300, y: 960)],
                                                              canvasFrame: stack.frame), in: app)
        try waitFor(app.descendants(matching: .any)["resultStars"], label: "0 of 3 stars")
        XCTAssertEqual(app.staticTexts["resultTitle"].label, "Almost! Try once more")
        keepScreenshot("lesson-result-redo")

        // Leave: still step 4 of 5 on the card.
        app.buttons["closeLesson"].tap()
        XCTAssertTrue(app.buttons["lesson-rocket"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lesson-rocket"].label.contains("Continue, step 4 of 5"))
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = extra + ["-smoothLines", "YES", "-pencilOnly", "NO", "-hideCanvasTips", "YES"]
        app.launch()
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height, Date() < deadline { usleep(100_000) }
        sleep(1)
        return app
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 6) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: timeout) != .completed {
            keepScreenshot("failed-waiting-for-\(label)")
            XCTFail("expected \(label), got \(element.exists ? element.label : "no element")")
            throw XCTSkip("stopping")
        }
    }

    @MainActor
    private func keepScreenshot(_ name: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
