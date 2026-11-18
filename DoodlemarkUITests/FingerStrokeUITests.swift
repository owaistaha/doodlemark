import XCTest

/// Draws on the DEBUG export screen with synthesized touches: the same
/// "finger" path the simulator uses for trackpad and mouse input. Answers
/// RISKS.md #9: what `size.width` PencilKit stores for a real touch stroke.
final class FingerStrokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFingerStrokeStoredWidth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-debugOpenExportTest", "YES"]
        app.launch()

        let canvas = app.descendants(matching: .any)["debugInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))

        // A long horizontal line, then a diagonal: two one-finger strokes.
        drag(on: canvas, from: (0.15, 0.30), to: (0.85, 0.30))
        drag(on: canvas, from: (0.20, 0.50), to: (0.80, 0.85))
        // And a tap, which should leave a dot.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.8)).tap()

        let status = app.staticTexts["debugStatus"]
        let stored = NSPredicate(format: "label CONTAINS '3 strokes' AND label CONTAINS 'size.width'")
        expectation(for: stored, evaluatedWith: status)
        waitForExpectations(timeout: 10)

        print("FINGERSTROKE| \(status.label)")
        XCTAssertEqual(Self.storedWidth(in: status.label), 10, "width-8 pen stores 10 (RISKS.md #9)")
        // The live canvas keeps monoline (only a data reload reports .pen, see DrawingPersistenceTests).
        XCTAssertTrue(status.label.contains("ink com.apple.ink.monoline"), status.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "debug-screen-after-finger-strokes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Maps the tool width to the stored `size.width` for several widths.
    /// Measured: stored = tool + 2 at every width (0.5 → 2.5, 8 → 10, 40 → 42).
    /// `LineSize.storedWidthOffset` depends on this; if it changes, update it.
    @MainActor
    func testToolWidthToStoredWidth() throws {
        for width in ["0.5", "2", "4", "6", "8", "12", "16", "24", "40"] {
            let app = XCUIApplication()
            app.launchArguments = ["-debugOpenExportTest", "YES", "-debugPenWidth", width]
            app.launch()
            let canvas = app.descendants(matching: .any)["debugInkCanvas"]
            XCTAssertTrue(canvas.waitForExistence(timeout: 10))
            drag(on: canvas, from: (0.15, 0.40), to: (0.85, 0.45))
            let status = app.staticTexts["debugStatus"]
            expectation(for: NSPredicate(format: "label CONTAINS 'size.width'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            print("TOOLWIDTH| tool \(width): \(status.label)")
            let stored = try XCTUnwrap(Self.storedWidth(in: status.label))
            XCTAssertEqual(stored, Double(width)! + 2, accuracy: 0.001, "tool \(width)")
            app.terminate()
        }
    }

    /// Reads "size.width 10.00 (min 10.00, max 10.00" and returns the value if
    /// every point stored the same width.
    static func storedWidth(in label: String) -> Double? {
        guard let match = label.firstMatch(of: /size\.width ([0-9.]+) \(min ([0-9.]+), max ([0-9.]+)/),
              let w = Double(match.1), Double(match.2) == w, Double(match.3) == w else { return nil }
        return w
    }

    @MainActor
    private func drag(on element: XCUIElement, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat)) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
