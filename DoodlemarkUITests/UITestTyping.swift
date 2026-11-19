import XCTest

extension XCUIElement {
    /// Types into a text field the way a person would: tap it (unless it's
    /// already being typed in), wait until it really has keyboard focus, the
    /// keyboard is up and the panel has stopped moving, then type, and wait
    /// for the field to show `expected`. No retries: if keys are lost, the
    /// test fails with what the field actually shows.
    @MainActor
    func typeWhenReady(_ text: String, in app: XCUIApplication, expect expected: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        if !hasKeyboardFocus { tap() }
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 5), .completed, "the field has keyboard focus", file: file, line: line)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is up", file: file, line: line)
        waitUntilStill()
        typeText(text)
        let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: self)
        if XCTWaiter().wait(for: [shows], timeout: 5) != .completed {
            XCTFail("the field shows \(String(describing: value)), expected \(expected)", file: file, line: line)
        }
    }

    /// Whether this element is the one the keyboard types into.
    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }

    /// Waits (up to 3 s) until the element's frame is the same twice 0.3 s
    /// apart: the keyboard's slide-in and the panel's scroll are over.
    @MainActor
    func waitUntilStill() {
        var last = frame
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            usleep(300_000)
            let now = frame
            if now == last { return }
            last = now
        }
    }
}
