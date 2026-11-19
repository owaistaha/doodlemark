import XCTest

/// Step 8 with real taps: three tips on the first canvas, each pointing at
/// its control, then never again; Skip ends them.
final class CanvasTipsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testThreeTipsOnTheFirstCanvasThenNeverAgain() throws {
        let app = launch(["-resetCanvasTips", "YES"])
        let card = app.descendants(matching: .any)["canvasTip"]
        let gotIt = app.buttons["tipGotIt"]
        let expected = [("Tip 1 of 3. Sketch it messy first", "tool-sketch"),
                        ("Tip 2 of 3. Then trace it clean", "tool-ink"),
                        ("Tip 3 of 3. Show it to the world", "previewExport")]
        for (index, (label, control)) in expected.enumerated() {
            XCTAssertTrue(card.waitForExistence(timeout: 5), label)
            try waitForLabel(card, label)
            // The card sits next to the control it talks about.
            let target = app.buttons[control].frame
            let box = card.frame
            if control == "previewExport" {
                XCTAssertGreaterThan(box.minY, target.maxY, "below Preview & export")
                XCTAssertLessThan(box.minY - target.maxY, 60)
            } else {
                XCTAssertGreaterThan(box.minX, target.maxX, "right of the \(control) tool")
                XCTAssertLessThan(box.minX - target.maxX, 60)
                XCTAssertTrue((box.minY...box.maxY).contains(target.midY), "level with it")
            }
            XCTAssertGreaterThanOrEqual(gotIt.frame.height, 56, "big Got it button")
            keepScreenshot("tip-\(index + 1)")
            gotIt.tap()
        }
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        // The canvas works right after.
        app.buttons["tool-shapes"].tap()
        XCTAssertTrue(app.buttons["add-star"].waitForExistence(timeout: 5))

        // Shown once: a relaunch (another new logo) has no tips.
        app.terminate()
        let again = launch([])
        XCTAssertFalse(again.descendants(matching: .any)["canvasTip"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSkipEndsTheTips() throws {
        let app = launch(["-resetCanvasTips", "YES"])
        let card = app.descendants(matching: .any)["canvasTip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["tipSkip"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        app.terminate()
        let again = launch([])
        XCTAssertFalse(again.descendants(matching: .any)["canvasTip"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTheCanvasIgnoresTouchesWhileATipIsUp() throws {
        let app = launch(["-resetCanvasTips", "YES"])
        XCTAssertTrue(app.descendants(matching: .any)["canvasTip"].waitForExistence(timeout: 5))
        let stack = app.descendants(matching: .any)["canvasStack"]
        let start = stack.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: stack.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        XCTAssertEqual(stack.value as? String, "Sketch: 0 lines. Ink: 0 lines.", "no stray line under the tips")
        XCTAssertTrue(app.descendants(matching: .any)["canvasTip"].exists, "and the tip stays up")
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-resetProjects", "YES", "-openNewLogo", "YES", "-smoothLines", "YES", "-pencilOnly", "NO"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["canvasStack"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height, Date() < deadline { usleep(100_000) }
        sleep(1)
        return app
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 5) != .completed {
            XCTFail("expected label \(label), got \(element.exists ? element.label : "no element")")
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
