import PencilKit
import XCTest
@testable import Doodlemark

/// The editor's change → undo logic, driven the way the canvas drives it.
@MainActor
final class CanvasModelTests: XCTestCase {
    /// These tests run inside the app, so the model's remembered toggles land
    /// in the app's own defaults. Put them back afterwards, or the next app
    /// launch on this simulator starts with Smooth my lines off.
    nonisolated private static let rememberedKeys = [CanvasModel.smoothLinesKey, CanvasModel.pencilOnlyKey]
    nonisolated(unsafe) private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedDefaults = [:]
        for key in Self.rememberedKeys {
            if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value }
        }
    }

    override func tearDown() {
        for key in Self.rememberedKeys {
            UserDefaults.standard.set(savedDefaults[key], forKey: key)
        }
        super.tearDown()
    }

    func testSmoothLinesIsOnByDefaultAndRemembered() {
        UserDefaults.standard.removeObject(forKey: CanvasModel.smoothLinesKey)
        XCTAssertTrue(CanvasModel(project: .blank()).smoothLines)
        CanvasModel(project: .blank()).smoothLines = false
        XCTAssertFalse(CanvasModel(project: .blank()).smoothLines)
        UserDefaults.standard.set("YES", forKey: CanvasModel.smoothLinesKey)   // a launch argument's form
        XCTAssertTrue(CanvasModel(project: .blank()).smoothLines)
    }

    private func model(smooth: Bool = false, mirror: Bool = false) -> CanvasModel {
        let model = CanvasModel(project: .blank())
        model.smoothLines = smooth
        model.mirrorOn = mirror
        return model
    }

    private func adding(_ stroke: PKStroke, to drawing: PKDrawing) -> PKDrawing {
        var copy = drawing
        copy.strokes.append(stroke)
        return copy
    }

    private let sketchStroke = PKStroke(ink: PKInk(.pencil, color: .gray),
                                        path: GateFixtures.underline.path)

    func testUndoRedoAcrossLayerSwitches() {
        let m = model()
        m.select(.ink)
        _ = m.inkDidChange(adding(GateFixtures.diagonal, to: m.ink))
        m.select(.sketch)
        m.sketchDidChange(adding(sketchStroke, to: m.sketch))
        m.select(.ink)
        _ = m.inkDidChange(adding(GateFixtures.arc, to: m.ink))
        XCTAssertEqual([m.sketch.strokes.count, m.ink.strokes.count], [1, 2])

        m.undo()   // the arc
        XCTAssertEqual([m.sketch.strokes.count, m.ink.strokes.count], [1, 1])
        m.undo()   // the sketch stroke, even though Ink is the active layer
        XCTAssertEqual([m.sketch.strokes.count, m.ink.strokes.count], [0, 1])
        m.undo()   // the diagonal
        XCTAssertEqual([m.sketch.strokes.count, m.ink.strokes.count], [0, 0])
        XCTAssertFalse(m.canUndo)

        m.redo(); m.redo(); m.redo()
        XCTAssertEqual([m.sketch.strokes.count, m.ink.strokes.count], [1, 2])
        XCTAssertFalse(m.canRedo)
        XCTAssertEqual(m.restoreRequest, 6, "every undo/redo asks the canvases to reload")
    }

    func testMirrorAddsTheCopyInTheSameUndoStep() {
        let m = model(mirror: true)
        let shown = m.inkDidChange(adding(GateFixtures.zigzag, to: m.ink))
        XCTAssertEqual(shown.strokes.count, 2)
        XCTAssertEqual(shown.strokes[1].transform, Symmetry.mirrored(shown.strokes[0]).transform)
        m.undo()
        XCTAssertEqual(m.ink.strokes.count, 0, "one undo removes the stroke and its mirror")
        m.redo()
        XCTAssertEqual(m.ink.strokes.count, 2)
    }

    func testSmoothThenMirrorTheSmoothedStroke() {
        let m = model(smooth: true, mirror: true)
        let raw = GateFixtures.wobbly
        let shown = m.inkDidChange(adding(raw, to: m.ink))
        let smoothed = StrokeSmoother.smoothed(raw)
        XCTAssertEqual(shown.strokes.count, 2)
        XCTAssertEqual(shown.strokes[0].path.map(\.location), smoothed.path.map(\.location), "first: the smoothed stroke")
        XCTAssertNotEqual(shown.strokes[0].path.map(\.location), raw.path.map(\.location))
        XCTAssertEqual(shown.strokes[1].path.map(\.location), smoothed.path.map(\.location), "second: same points…")
        XCTAssertEqual(shown.strokes[1].transform, Symmetry.mirrored(smoothed).transform, "…mirrored")
        m.undo()
        XCTAssertTrue(m.ink.strokes.isEmpty, "smoothing + mirror is still one undo step")
    }

    func testSmoothingIsInkOnlyAndCanBeOff() {
        let off = model(smooth: false)
        let raw = GateFixtures.wobbly
        XCTAssertEqual(off.inkDidChange(adding(raw, to: off.ink)).strokes[0].path.map(\.location),
                       raw.path.map(\.location))
        let on = model(smooth: true)
        on.sketchDidChange(adding(raw, to: on.sketch))
        XCTAssertEqual(on.sketch.strokes[0].path.map(\.location), raw.path.map(\.location), "Sketch is never smoothed")
    }

    func testErasingDoesNotMirrorOrSmooth() {
        let m = model(smooth: true, mirror: true)
        _ = m.inkDidChange(adding(GateFixtures.zigzag, to: m.ink))
        var erased = m.ink
        erased.strokes.removeLast()
        XCTAssertEqual(m.inkDidChange(erased).strokes.count, 1)
    }

    func testOneEraserDragIsOneUndoStep() {
        let m = model()
        for stroke in [GateFixtures.diagonal, GateFixtures.arc, GateFixtures.zigzag] {
            _ = m.inkDidChange(adding(stroke, to: m.ink))
        }
        m.beginToolUse()
        var drawing = m.ink
        drawing.strokes.removeLast(); _ = m.inkDidChange(drawing)
        drawing.strokes.removeLast(); _ = m.inkDidChange(drawing)
        m.endToolUse()
        XCTAssertEqual(m.ink.strokes.count, 1)
        m.undo()
        XCTAssertEqual(m.ink.strokes.count, 3, "both erased lines come back with one undo")
    }

    func testGridAndMirrorAreNeverInTheSVG() throws {
        let m = model(mirror: false)
        _ = m.inkDidChange(adding(GateFixtures.zigzag, to: m.ink))
        m.project.shapes = GateFixtures.allShapes
        m.project.text = Fixtures.pizzaText(center: CGPoint(x: 512, y: 880))
        let plain = try SVGExporter.svg(project: m.project, ink: m.ink)
        m.gridOn = true
        m.mirrorOn = true
        XCTAssertEqual(try SVGExporter.svg(project: m.project, ink: m.ink), plain, "guides are on screen only")
        XCTAssertFalse(plain.contains("grid"))
    }
}
