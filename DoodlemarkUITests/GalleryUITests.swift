import XCTest

/// Step 6 with real touches: the gallery, New logo, saving, and the PRD
/// metric (the project is still there after the app is killed and relaunched,
/// and opens exactly as it was).
final class GalleryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The PRD success metric, start to finish.
    @MainActor
    func testNewLogoSurvivesTerminateAndRelaunchAndOpensIdentical() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.descendants(matching: .any)["emptyGallery"].waitForExistence(timeout: 10), "first launch: empty state")
        keepScreenshot("gallery-empty")

        app.buttons["emptyNewLogo"].tap()
        XCTAssertTrue(app.buttons["startDrawing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectedStart"].label, "Selected: Blank canvas")
        app.buttons["prompt-pizza-rocket"].tap()
        XCTAssertEqual(app.staticTexts["selectedStart"].label, "Selected: A pizza delivery rocket")
        keepScreenshot("new-logo")
        app.buttons["startDrawing"].tap()

        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        let title = app.buttons["projectTitle"].label
        XCTAssertTrue(title.hasPrefix("A pizza delivery rocket, Not saved yet"),
                      "named after the prompt; nothing written yet: \(title)")

        // All four layers, plus Grid.
        app.buttons["tool-sketch"].tap()
        drag(stack, (0.15, 0.8), (0.45, 0.9))
        app.buttons["tool-ink"].tap()
        drag(stack, (0.15, 0.15), (0.85, 0.25))
        app.buttons["tool-shapes"].tap()
        app.buttons["add-star"].tap()
        app.buttons["tool-text"].tap()
        let field = app.textFields["textField"]
        field.tap()
        field.typeText("Pizza Rocket")
        hideKeyboard(app)
        app.buttons["grid"].tap()
        app.buttons["tool-ink"].tap()

        try waitFor(app.buttons["projectTitle"], label: "A pizza delivery rocket, Saved")   // the 1 s autosave
        let before = document(app)
        XCTAssertTrue(before.contains("sketch 1 lines"), before)
        XCTAssertTrue(before.contains("grid on"), before)
        let shapes = app.descendants(matching: .any)["debugShapes"].label
        let text = app.descendants(matching: .any)["debugText"].label
        let colors = app.descendants(matching: .any)["debugColors"].label
        let lines = stack.value as? String
        XCTAssertEqual(lines, "Sketch: 1 line. Ink: 1 line.")
        XCTAssertEqual(shapes, "1 shapes")
        XCTAssertTrue(text.hasPrefix("text Pizza Rocket; LilitaOne"), text)

        app.buttons["back"].tap()
        let card = app.buttons.matching(identifier: "projectCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "A pizza delivery rocket, Edited today")
        keepScreenshot("gallery-one-logo")

        // Killed (like a force-quit) and opened again.
        app.terminate()
        let again = launch(reset: false)
        let reopenedCard = again.buttons.matching(identifier: "projectCard").firstMatch
        XCTAssertTrue(reopenedCard.waitForExistence(timeout: 10), "still in the gallery")
        XCTAssertEqual(again.buttons.matching(identifier: "projectCard").count, 1)
        reopenedCard.tap()
        let reopenedStack = again.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(reopenedStack.waitForExistence(timeout: 5))
        XCTAssertEqual(document(again), before, "same SVG (ink, shapes, text, palette), sketch, Mirror, Grid, name")
        XCTAssertEqual(reopenedStack.value as? String, lines)
        XCTAssertEqual(again.descendants(matching: .any)["debugShapes"].label, shapes)
        XCTAssertEqual(again.descendants(matching: .any)["debugText"].label, text)
        XCTAssertEqual(again.descendants(matching: .any)["debugColors"].label, colors)
        XCTAssertEqual(again.buttons["grid"].value as? String, "On")
        XCTAssertTrue(again.buttons["projectTitle"].label.hasPrefix("A pizza delivery rocket, Saved"))
        keepScreenshot("canvas-reopened")
    }

    /// No Back: the 1 s autosave alone is enough to survive being killed.
    @MainActor
    func testAutosaveAloneSurvivesBeingKilled() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.buttons["newLogo"].waitForExistence(timeout: 10))
        app.buttons["newLogo"].tap()
        XCTAssertTrue(app.buttons["startDrawing"].waitForExistence(timeout: 5))
        app.buttons["startDrawing"].tap()                      // blank canvas
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        drag(stack, (0.2, 0.5), (0.8, 0.5))
        try waitFor(app.buttons["projectTitle"], label: "Untitled logo, Saved")
        let before = document(app)
        app.terminate()

        let again = launch(reset: false)
        let card = again.buttons.matching(identifier: "projectCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.label, "Untitled logo, Edited today")
        card.tap()
        XCTAssertTrue(again.descendants(matching: .any)["canvasStack"].waitForExistence(timeout: 5))
        XCTAssertEqual(document(again), before)
    }

    /// Rename, Duplicate and Delete from a card's menu, the broken-project
    /// card, the Learn tab and Shuffle. Screenshots for the report.
    @MainActor
    func testCardMenuBrokenCardLearnAndShuffle() throws {
        let app = launch(reset: true, extra: ["-seedSampleProjects", "YES", "-seedBrokenProject", "YES"])
        let cards = app.buttons.matching(identifier: "projectCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.firstMatch.label, "Pizza Rocket, Edited today", "newest edited first")
        sleep(1)                                               // thumbnails decode
        keepScreenshot("gallery-with-broken-card")
        let count = cards.count

        cards.firstMatch.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Duplicate"].waitForExistence(timeout: 3))
        keepScreenshot("gallery-card-menu")
        app.buttons["Duplicate"].tap()
        try waitFor(cards.firstMatch, label: "Pizza Rocket copy, Edited today")
        XCTAssertEqual(cards.count, count + 1)

        cards.firstMatch.press(forDuration: 1.2)
        app.buttons["Rename"].tap()
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.clearAndType("Rocket Two")
        app.alerts.buttons["Rename"].tap()
        try waitFor(cards.firstMatch, label: "Rocket Two, Edited today")

        cards.firstMatch.press(forDuration: 1.2)
        // The menu's Delete, not the broken card's own Delete button.
        app.buttons.matching(NSPredicate(format: "label == 'Delete' AND identifier != 'deleteBroken'")).firstMatch.tap()
        let confirm = app.alerts["Delete \u{201C}Rocket Two\u{201D}?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        keepScreenshot("gallery-delete-confirm")
        confirm.buttons["Delete"].tap()
        try waitFor(cards.firstMatch, label: "Pizza Rocket, Edited today")
        XCTAssertEqual(cards.count, count)

        // The damaged project: shown, not dropped, and it can be deleted.
        // (Its folder is the newest, so it's in the first row.)
        let deleteBroken = app.buttons["deleteBroken"]
        XCTAssertTrue(deleteBroken.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Couldn't open this logo"].exists)
        deleteBroken.tap()
        let confirmBroken = app.alerts["Delete this logo?"]
        XCTAssertTrue(confirmBroken.waitForExistence(timeout: 3))
        confirmBroken.buttons["Delete"].tap()
        XCTAssertTrue(deleteBroken.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Couldn't open this logo"].exists)
        XCTAssertEqual(cards.count, count, "only the broken one went")

        app.buttons["tab-learn"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["learnComingSoon"].waitForExistence(timeout: 3))
        keepScreenshot("learn-coming-soon")
        app.buttons["tab-myLogos"].tap()

        // A chip starts a new logo with that prompt straight away.
        app.buttons["chip-cat-cafe"].tap()
        XCTAssertTrue(app.buttons["projectTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["projectTitle"].label.hasPrefix("A café run by cats"), app.buttons["projectTitle"].label)
        app.buttons["back"].tap()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(cards.firstMatch.label, "Pizza Rocket, Edited today", "an untouched new logo isn't saved")

        app.buttons["newLogo"].tap()
        let shownBefore = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'prompt-'"))
            .allElementsBoundByIndex.map(\.identifier))
        XCTAssertEqual(shownBefore.count, 9)
        app.buttons["shuffle"].tap()
        sleep(1)
        let shownAfter = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'prompt-'"))
            .allElementsBoundByIndex.map(\.identifier))
        XCTAssertEqual(shownAfter.count, 9)
        XCTAssertNotEqual(shownAfter, shownBefore, "Shuffle swaps in the 10th prompt")
        keepScreenshot("new-logo-shuffled")
    }

    // MARK: Helpers

    @MainActor
    private func launch(reset: Bool, extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-resetProjects", "YES"] : []) + extra
            + ["-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        // Wait for the turn to landscape. (A predicate on "frame.size.width"
        // never matches, so it used to wait the full 5 s.)
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height, Date() < deadline { usleep(100_000) }
        sleep(1)
        return app
    }

    @MainActor
    private func document(_ app: XCUIApplication) -> String {
        sleep(1)
        return app.descendants(matching: .any)["debugDocument"].label
    }

    @MainActor
    private func drag(_ element: XCUIElement, _ from: (Double, Double), _ to: (Double, Double)) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    @MainActor
    private func hideKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let hide = app.keyboards.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'keyboard'")).firstMatch
        if hide.exists { hide.tap() } else { app.keyboards.buttons["Done"].firstMatch.tap() }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 6) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: timeout) != .completed {
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

private extension XCUIElement {
    /// Selects everything in a text field and types over it.
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
