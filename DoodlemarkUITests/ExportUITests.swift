import XCTest

/// Step 7 with real taps: "Preview & export" refuses an empty (or
/// sketch-only) logo, opens the mockups for a real one, and "Export & share"
/// opens the system share sheet with the right files, removed once it closes.
final class ExportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testNothingToExportSaysDrawSomethingFirst() throws {
        let (app, stack) = launchOnNewLogo()
        app.buttons["previewExport"].tap()
        try expectDrawSomethingFirst(app, "empty-export")

        // A sketch alone still counts as nothing: it's never exported.
        app.buttons["tool-sketch"].tap()
        drag(stack, (0.3, 0.3), (0.6, 0.4))
        try waitForValue(stack, "Sketch: 1 line. Ink: 0 lines.")
        app.buttons["previewExport"].tap()
        try expectDrawSomethingFirst(app, nil)
    }

    @MainActor
    func testExportAndShareOpensTheShareSheetWithTheFiles() throws {
        let (app, stack) = launchOnNewLogo()
        selectTool(app, "shapes")
        app.buttons["add-circle"].tap()
        selectTool(app, "ink")
        drag(stack, (0.35, 0.35), (0.65, 0.65))
        try waitForValue(stack, "Sketch: 0 lines. Ink: 1 line.")
        app.buttons["tool-sketch"].tap()
        drag(stack, (0.1, 0.9), (0.3, 0.9))                 // a sketch line that must not be exported
        try waitForValue(stack, "Sketch: 1 line. Ink: 1 line.")

        app.buttons["previewExport"].tap()
        XCTAssertTrue(app.buttons["backToDrawing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exportTitle"].label, "Untitled logo, out in the world")
        for mockup in ["mockupAppIcon", "mockupSticker", "mockupTiny", "mockupLightDark"] {
            XCTAssertTrue(app.descendants(matching: .any)[mockup].exists, mockup)
        }
        let savesAs = app.staticTexts["savesAs"]
        XCTAssertEqual(savesAs.label, "Saves untitled-logo.svg and untitled-logo.png")
        keepScreenshot("export-screen")

        // At least one format: unticking both turns Export & share off.
        app.buttons["formatSVG"].tap()
        app.buttons["formatPNG"].tap()
        try waitForLabel(savesAs, "Pick SVG, PNG or both.")
        XCTAssertFalse(app.buttons["exportAndShare"].isEnabled)
        XCTAssertFalse(app.buttons["transparentBackground"].isEnabled, "PNG only")
        keepScreenshot("export-no-format")
        app.buttons["formatSVG"].tap()
        app.buttons["formatPNG"].tap()

        // The typed name is cleaned.
        let field = app.textFields["fileName"]
        field.typeWhenReady(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Space Cat/2!", in: app,
                            expect: "Space Cat/2!")
        try waitForLabel(savesAs, "Saves Space-Cat-2.svg and Space-Cat-2.png")
        hideKeyboard(app)

        app.buttons["exportAndShare"].tap()
        let probe = app.descendants(matching: .any)["debugExport"]
        try waitForLabel(probe, "files Space-Cat-2.svg, Space-Cat-2.png; sharing yes; on disk yes")
        XCTAssertTrue(shareSheet(app).waitForExistence(timeout: 10), "the system share sheet is up")
        keepScreenshot("share-sheet")

        // Closing it (tap outside the popover) removes the temp files.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertTrue(shareSheet(app).waitForNonExistence(timeout: 10))
        try waitForLabel(probe, "files Space-Cat-2.svg, Space-Cat-2.png; sharing no; on disk no")

        app.buttons["backToDrawing"].tap()
        XCTAssertTrue(app.buttons["previewExport"].waitForExistence(timeout: 5), "back on the canvas")
        try waitForValue(stack, "Sketch: 1 line. Ink: 1 line.")
    }

    /// A saved sample logo from the gallery: the title and file name follow
    /// the project name, and all four mockups fit on the landscape screen.
    @MainActor
    func testASavedLogoOpensItsExportScreen() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-resetProjects", "YES", "-hideCanvasTips", "YES", "-seedSampleProjects", "YES"]
        app.launch()
        let card = app.buttons.matching(identifier: "projectCard").firstMatch    // newest first: Pizza Rocket
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let preview = app.buttons["previewExport"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        XCTAssertTrue(app.staticTexts["exportTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exportTitle"].label, "Pizza Rocket, out in the world")
        XCTAssertEqual(app.staticTexts["savesAs"].label, "Saves pizza-rocket.svg and pizza-rocket.png")
        let window = app.windows.firstMatch.frame
        for mockup in ["mockupAppIcon", "mockupSticker", "mockupTiny", "mockupLightDark"] {
            let frame = app.descendants(matching: .any)[mockup].frame
            XCTAssertTrue(window.contains(frame), "\(mockup) fits on screen: \(frame) in \(window)")
        }
        keepScreenshot("export-pizza-rocket")
    }

    // MARK: Helpers

    @MainActor
    private func launchOnNewLogo() -> (XCUIApplication, XCUIElement) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-resetProjects", "YES", "-hideCanvasTips", "YES", "-openNewLogo", "YES", "-smoothLines", "YES", "-pencilOnly", "NO"]
        app.launch()
        let stack = app.descendants(matching: .any)["canvasStack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height, Date() < deadline { usleep(100_000) }
        sleep(1)
        return (app, stack)
    }

    /// Taps a tool and checks it took (the first tap after launch can be lost:
    /// see CanvasScreenUITests).
    @MainActor
    private func selectTool(_ app: XCUIApplication, _ tool: String) {
        let button = app.buttons["tool-\(tool)"]
        for _ in 0..<3 where !button.isSelected {
            button.tap()
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"),
                                                                 object: button)], timeout: 2)
        }
        XCTAssertTrue(button.isSelected, "tool \(tool)")
    }

    @MainActor
    private func expectDrawSomethingFirst(_ app: XCUIApplication, _ screenshot: String?) throws {
        let alert = app.alerts["Draw something first."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        if let screenshot { keepScreenshot(screenshot) }
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["backToDrawing"].exists, "the export screen didn't open")
        XCTAssertFalse(shareSheet(app).exists, "and no share sheet")
    }

    /// UIActivityViewController's list, wherever the system puts it.
    @MainActor
    private func shareSheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'ActivityListView' OR identifier == 'Share' OR label == 'Save to Files'")).firstMatch
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
    private func waitForLabel(_ element: XCUIElement, _ label: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 6) != .completed {
            XCTFail("expected label \(label), got \(element.exists ? element.label : "no element")")
        }
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 6) != .completed {
            XCTFail("expected \(value), got \(element.value ?? "nil")")
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
