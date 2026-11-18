import PencilKit
import XCTest
@testable import Doodlemark

/// Step 5b in the editor: adding, picking and editing shapes, one undo step
/// per gesture, and what reaches the SVG.
@MainActor
final class ShapeModelTests: XCTestCase {
    private func shapesModel() -> CanvasModel {
        let model = CanvasModel(project: .blank())
        model.select(.shapes)
        return model
    }

    /// A gesture the way the canvas drives it: begin, several live updates, end.
    private func gesture(_ model: CanvasModel, _ steps: [(LogoShape) -> LogoShape]) {
        let start = model.selectedShape!
        model.beginEdit()
        for step in steps { model.updateShape(step(start)) }
        model.endEdit()
    }

    func testAddShapePutsItAtTheCentreInTheCurrentColorAndPicksIt() {
        let model = shapesModel()
        model.chooseSlot(.third)
        model.toggleVisibility(.shapes)                   // hidden…
        model.addShape(.star)
        let star = model.project.shapes[0]
        XCTAssertEqual(star.kind, .star)
        XCTAssertEqual(star.center, CGPoint(x: 512, y: 512))
        XCTAssertEqual(star.size, ShapeEditing.newShapeSize)
        XCTAssertEqual(star.rotation, 0)
        XCTAssertEqual(star.fill, .third)
        XCTAssertEqual(model.selectedShape, star)
        XCTAssertFalse(model.hiddenLayers.contains(.shapes), "…shown again so you see what you added")
        XCTAssertEqual(model.history.undoStack.count, 1)

        model.undo()
        XCTAssertTrue(model.project.shapes.isEmpty)
        XCTAssertNil(model.selectedShape, "nothing left to pick")
    }

    func testEveryMoveScaleOrTurnGestureIsOneUndoStep() {
        let model = shapesModel()
        model.addShape(.triangle)
        let added = model.selectedShape!

        gesture(model, [{ ShapeEditing.moved($0, by: CGPoint(x: 10, y: 0), snapDistance: 0).shape },
                        { ShapeEditing.moved($0, by: CGPoint(x: 60, y: 30), snapDistance: 0).shape },
                        { ShapeEditing.moved($0, by: CGPoint(x: 100, y: 40), snapDistance: 0).shape }])
        let moved = model.selectedShape!
        gesture(model, [{ ShapeEditing.resized($0, by: 1.2) }, { ShapeEditing.resized($0, by: 1.5) }])
        let scaled = model.selectedShape!
        gesture(model, [{ ShapeEditing.rotated($0, by: 0.2) }, { ShapeEditing.rotated($0, by: 0.8) }])

        XCTAssertEqual(moved.center, CGPoint(x: 612, y: 552))
        XCTAssertEqual(scaled.size, 480, accuracy: 1e-9)
        XCTAssertEqual(model.selectedShape!.rotation, 45 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(model.history.undoStack.count, 4, "add + three gestures")

        model.undo()
        XCTAssertEqual(model.selectedShape, scaled, "undoes the whole turn")
        model.undo()
        XCTAssertEqual(model.selectedShape, moved)
        model.undo()
        XCTAssertEqual(model.selectedShape, added)
        model.redo()
        XCTAssertEqual(model.selectedShape, moved)
    }

    func testOneFingerTurningIntoTwoFingersIsStillOneStep() {
        let model = shapesModel()
        model.addShape(.circle)
        let start = model.selectedShape!
        model.beginEdit()                                         // one-finger drag
        model.updateShape(ShapeEditing.moved(start, by: CGPoint(x: 50, y: 0), snapDistance: 0).shape)
        model.beginEdit()                                         // second finger lands on it
        model.endEdit()                                           // the drag is cancelled
        model.updateShape(ShapeEditing.resized(model.selectedShape!, by: 2))
        model.endEdit()                                           // fingers lifted
        XCTAssertEqual(model.history.undoStack.count, 2)
        model.undo()
        XCTAssertEqual(model.selectedShape, start)
    }

    func testAGestureThatChangesNothingIsNoStep() {
        let model = shapesModel()
        model.addShape(.circle)
        model.beginEdit()
        model.updateShape(model.selectedShape!)
        model.endEdit()
        XCTAssertEqual(model.history.undoStack.count, 1)
    }

    func testSnapGuidesShowOnlyDuringTheGesture() {
        let model = shapesModel()
        model.addShape(.circle)
        model.beginEdit()
        let result = ShapeEditing.moved(model.selectedShape!, by: CGPoint(x: 4, y: 300), snapDistance: 10)
        model.updateShape(result.shape, guides: result.guides)
        XCTAssertEqual(model.snapGuides, SnapGuides(vertical: true, horizontal: false))
        model.endEdit()
        XCTAssertEqual(model.snapGuides, SnapGuides())
    }

    func testTapOnASwatchFillsThePickedShapeInOneStep() {
        let model = shapesModel()
        model.addShape(.circle)
        model.chooseSlot(.first)
        XCTAssertEqual(model.selectedShape?.fill, .first)
        XCTAssertEqual(model.history.undoStack.count, 2)
        model.chooseSlot(.first)
        XCTAssertEqual(model.history.undoStack.count, 2, "same color again: no step")
        model.undo()
        XCTAssertEqual(model.selectedShape?.fill, .second)

        model.selectShape(nil)
        model.chooseSlot(.third)
        XCTAssertEqual(model.project.shapes[0].fill, .second, "nothing picked: only the current color changes")
    }

    func testFlipAndDelete() {
        let model = shapesModel()
        model.addShape(.star)
        XCTAssertFalse(model.canFlipSelectedShape(sideways: true), "an upright star looks the same mirrored")
        model.flipSelectedShape(sideways: true)
        XCTAssertEqual(model.history.undoStack.count, 1, "a flip that changes nothing is no step")
        XCTAssertTrue(model.canFlipSelectedShape(sideways: false))
        model.flipSelectedShape(sideways: false)
        XCTAssertEqual(model.selectedShape!.rotation, .pi, accuracy: 1e-9)

        model.deleteSelectedShape()
        XCTAssertTrue(model.project.shapes.isEmpty)
        XCTAssertNil(model.selectedShape)
        model.undo()
        XCTAssertEqual(model.project.shapes.count, 1)
        XCTAssertEqual(model.project.shapes[0].rotation, .pi, accuracy: 1e-9)
    }

    func testLeavingTheShapesToolDropsThePick() {
        let model = shapesModel()
        model.addShape(.circle)
        model.select(.ink)
        XCTAssertNil(model.selectedShape)
        XCTAssertNil(model.stackConfig.selection)
    }

    func testSelectionBoundsAreThePathBounds() {
        let model = shapesModel()
        model.addShape(.star)
        XCTAssertEqual(model.stackConfig.selection, ShapeEditing.bounds(of: model.selectedShape!))
        model.toggleVisibility(.shapes)
        XCTAssertNil(model.stackConfig.selection, "no handles on a hidden layer")
    }

    /// Shapes added and edited in the editor export with exactly the geometry
    /// `ShapeGeometry` draws on screen, filled with their slot's color.
    func testShapesInTheSVG() throws {
        let model = shapesModel()
        model.addShape(.circle)
        gesture(model, [{ ShapeEditing.moved($0, by: CGPoint(x: -200, y: -150), snapDistance: 0).shape }])
        model.selectShape(nil)                      // so the swatch doesn't refill the circle
        model.chooseSlot(.first)
        model.addShape(.star)
        gesture(model, [{ ShapeEditing.transformed($0, translation: CGPoint(x: 150, y: 120), scale: 0.75,
                                                   rotation: 0.5, snapDistance: 0).shape }])
        model.flipSelectedShape(sideways: false)

        let svg = try SVGExporter.svg(project: model.project, ink: model.ink)
        let lines = svg.split(separator: "\n").map(String.init)
        let group = try XCTUnwrap(lines.firstIndex(of: #"  <g id="shapes">"#))
        for (offset, shape) in model.project.shapes.enumerated() {
            let fill = model.project.color(for: shape.fill).hexString
            let d = SVGExporter.pathData(ShapeGeometry.path(for: shape))
            XCTAssertEqual(lines[group + 1 + offset], #"    <path fill="\#(fill)" d="\#(d)"/>"#, "\(shape.kind)")
        }
        XCTAssertEqual(lines[group + 3], "  </g>")
        XCTAssertTrue(svg.contains(#"fill="\#(Fixtures.ink.hexString)""#), "the circle: color 2")
        XCTAssertTrue(svg.contains(#"fill="\#(Fixtures.tangerine.hexString)""#), "the star: color 1")
    }
}
