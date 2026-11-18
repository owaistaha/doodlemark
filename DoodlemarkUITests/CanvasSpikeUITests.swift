import XCTest

/// Drives the DEBUG canvas spike (step 4a) with synthesized touches and
/// reads its status line. Findings are recorded in RISKS.md #1 and #4.
final class CanvasSpikeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Mirror + undo

    /// Documents PencilKit's own undo with a programmatically appended mirror
    /// stroke (iPadOS 26.5): plain strokes undo fine, but after the append one
    /// undo changes nothing and PencilKit's undo stack is empty, so the pair
    /// can never be undone. That's why the canvas uses its own undo stack.
    @MainActor
    func testMirrorUndoWithPencilKitUndo() throws {
        let spike = Spike(undoMode: "pencilKit")
        // Control: without mirror, PencilKit's undo works in this stack.
        spike.drag(from: (0.60, 0.70), to: (0.85, 0.80))
        try spike.wait(for: "ink=1")
        spike.tap("spikeUndo")
        try spike.wait(for: "ink=0")
        spike.tap("spikeRedo")
        try spike.wait(for: "ink=1")
        print("SPIKE| pencilKit control (no mirror) undo+redo works: \(spike.status)")
        spike.tap("spikeUndo")
        try spike.wait(for: "ink=0")

        spike.tap("spikeMirror")
        spike.drag(from: (0.15, 0.30), to: (0.40, 0.45))
        try spike.wait(for: "ink=2")
        print("SPIKE| pencilKit after draw+mirror: \(spike.status)")
        spike.tap("spikeUndo")
        sleep(1)
        print("SPIKE| pencilKit after 1 undo: \(spike.status)")
        XCTAssertEqual(spike.value("ink"), 2, "if PencilKit now undoes the pair, revisit RISKS.md #1")
        XCTAssertEqual(spike.value("pkCanUndo"), 0)
        spike.tap("spikeUndo")
        sleep(1)
        print("SPIKE| pencilKit after 2 undos: \(spike.status)")
        spike.tap("spikeRedo")
        sleep(1)
        print("SPIKE| pencilKit after redo: \(spike.status)")
    }

    /// Our own undo stack: one undo removes the stroke and its mirror together.
    @MainActor
    func testMirrorUndoWithOwnUndoStack() throws {
        let spike = Spike(undoMode: "own")
        spike.tap("spikeMirror")
        spike.drag(from: (0.15, 0.30), to: (0.40, 0.45))
        try spike.wait(for: "ink=2")
        spike.drag(from: (0.10, 0.70), to: (0.35, 0.60))
        try spike.wait(for: "ink=4")
        print("SPIKE| own after 2 strokes+mirror: \(spike.status)")
        XCTAssertEqual(spike.value("pkCanUndo"), 0, "PencilKit must not register undo when our stack is in charge")

        spike.tap("spikeUndo")
        try spike.wait(for: "ink=2")
        spike.tap("spikeUndo")
        try spike.wait(for: "ink=0")
        spike.tap("spikeRedo")
        try spike.wait(for: "ink=2")
        spike.tap("spikeRedo")
        try spike.wait(for: "ink=4")
        print("SPIKE| own after undo, undo, redo, redo: \(spike.status)")
        XCTAssertEqual(spike.value("pkCanUndo"), 0)
    }

    // MARK: Layer touch routing

    @MainActor
    func testOnlyTheActiveLayerGetsTouchesAndLayersZoomTogether() throws {
        let spike = Spike(undoMode: "own")

        // Ink is active: a drag over the square draws ink, doesn't move the square.
        spike.drag(from: (0.18, 0.25), to: (0.45, 0.25))
        try spike.wait(for: "ink=1")
        XCTAssertEqual(spike.value("sketch"), 0)
        XCTAssertEqual(spike.value("squareMoves"), 0)
        print("SPIKE| ink drag: \(spike.status)")

        // Sketch active: draws on Sketch only.
        spike.tap("spikeLayer-Sketch")
        spike.drag(from: (0.20, 0.60), to: (0.60, 0.70))
        try spike.wait(for: "sketch=1")
        XCTAssertEqual(spike.value("ink"), 1)
        XCTAssertEqual(spike.value("squareMoves"), 0)

        // Shapes active: dragging the square moves it, nobody draws.
        spike.tap("spikeLayer-Shapes")
        spike.drag(from: (0.254, 0.254), to: (0.45, 0.50))
        try spike.wait(for: "squareMoves=1")
        XCTAssertEqual(spike.value("ink"), 1)
        XCTAssertEqual(spike.value("sketch"), 1)
        print("SPIKE| shapes drag: \(spike.status)")

        // Two-finger pinch with each layer active: zooms everything together,
        // leaves no stray marks, and keeps all layers aligned.
        for layer in ["Shapes", "Sketch", "Ink"] {
            spike.tap("spikeLayer-\(layer)")
            let before = spike.value("zoomx") ?? 0
            spike.stack.pinch(withScale: 1.6, velocity: 1)
            sleep(1)
            print("SPIKE| pinch with \(layer) active: \(spike.status)")
            XCTAssertGreaterThan(spike.value("zoomx") ?? 0, before + 0.1, "pinch should zoom (\(layer))")
            XCTAssertEqual(spike.value("ink"), 1, "pinch must not draw ink (\(layer))")
            XCTAssertEqual(spike.value("sketch"), 1, "pinch must not draw sketch (\(layer))")
            XCTAssertEqual(spike.value("squareMoves"), 1, "pinch must not move the square (\(layer))")
            XCTAssertLessThan(spike.value("align") ?? 99, 0.01, "layers out of line (\(layer))")
        }

        // Drawing while zoomed: lands under the finger, same stored width.
        spike.drag(from: (0.30, 0.40), to: (0.70, 0.45))
        try spike.wait(for: "ink=2")
        print("SPIKE| ink drag while zoomed: \(spike.status)")
        XCTAssertLessThan(spike.value("touch") ?? 99, 1.0, "stroke should start under the finger (view points)")
        XCTAssertEqual(spike.value("stored"), 10, "tool 8 should still store 10 when zoomed")
        XCTAssertLessThan(spike.value("align") ?? 99, 0.01)

        let shot = XCTAttachment(screenshot: spike.app.screenshot())
        shot.name = "spike-zoomed"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// Small driver for the spike screen.
@MainActor
private struct Spike {
    let app = XCUIApplication()

    init(undoMode: String) {
        app.launchArguments = ["-debugOpenCanvasSpike", "YES", "-spikeUndoMode", undoMode]
        app.launch()
        XCTAssertTrue(stack.waitForExistence(timeout: 10))
    }

    var stack: XCUIElement { app.descendants(matching: .any)["spikeStack"] }
    var status: String { app.staticTexts["spikeStatus"].label }

    func tap(_ id: String) { app.buttons[id].tap() }

    func drag(from: (CGFloat, CGFloat), to: (CGFloat, CGFloat)) {
        let start = stack.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let end = stack.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func wait(for token: String, timeout: TimeInterval = 5) throws {
        let label = app.staticTexts["spikeStatus"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if label.label.split(separator: " ").contains(Substring(token)) { return }
            usleep(100_000)
        }
        XCTFail("status never showed \(token): \(label.label)")
        throw XCTSkip("stopping")
    }

    func value(_ key: String) -> Double? {
        for part in status.split(separator: " ") where part.hasPrefix(key + "=") {
            return Double(part.dropFirst(key.count + 1).split(separator: ",").first ?? "")
        }
        return nil
    }
}
