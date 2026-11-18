import XCTest
@testable import Doodlemark

/// Step 5b: moving, resizing, turning, snapping, flipping and picking shapes.
final class ShapeEditingTests: XCTestCase {
    private func shape(_ kind: LogoShape.Kind, at center: CGPoint, size: CGFloat = 200,
                       rotation: Double = 0) -> LogoShape {
        LogoShape(id: UUID(), kind: kind, center: center, size: size, rotation: rotation, fill: .first)
    }

    private let degree = Double.pi / 180
    /// Outer radius 1 → how far a regular star's bottom points reach (cos 36°).
    private let starBottom = cos(Double.pi / 5)

    // MARK: Geometry after move / scale / rotate

    func testMoveKeepsSizeAndRotationAndMovesThePath() {
        let start = shape(.triangle, at: CGPoint(x: 300, y: 300), rotation: 0.3)
        let moved = ShapeEditing.moved(start, by: CGPoint(x: 100, y: 50), snapDistance: 0).shape
        XCTAssertEqual(moved.center, CGPoint(x: 400, y: 350))
        XCTAssertEqual(moved.size, start.size)
        XCTAssertEqual(moved.rotation, start.rotation)
        let a = ShapeEditing.bounds(of: start), b = ShapeEditing.bounds(of: moved)
        XCTAssertEqual(b.minX - a.minX, 100, accuracy: 1e-9)
        XCTAssertEqual(b.minY - a.minY, 50, accuracy: 1e-9)
        XCTAssertEqual(b.size.width, a.size.width, accuracy: 1e-9)
    }

    func testMoveKeepsTheCentreOnTheCanvas() {
        let moved = ShapeEditing.moved(shape(.circle, at: CGPoint(x: 900, y: 100)),
                                       by: CGPoint(x: 500, y: -500), snapDistance: 0).shape
        XCTAssertEqual(moved.center, CGPoint(x: 1024, y: 0))
    }

    func testCornerHandleScalesAroundTheCentreAndTheCornerFollowsTheFinger() throws {
        let start = shape(.roundedSquare, at: CGPoint(x: 512, y: 512), size: 200)
        let corner = try XCTUnwrap(ShapeEditing.handles(of: start).last)          // bottom-left (412, 612)
        XCTAssertEqual(corner, CGPoint(x: 412, y: 612))
        let scaled = ShapeEditing.scaled(start, handle: corner, finger: CGPoint(x: 312, y: 712))
        XCTAssertEqual(scaled.size, 400, accuracy: 1e-9, "twice as far from the centre = twice as big")
        XCTAssertEqual(scaled.center, start.center)
        let newCorner = try XCTUnwrap(ShapeEditing.handles(of: scaled).last)
        XCTAssertEqual(newCorner.x, 312, accuracy: 1e-9)
        XCTAssertEqual(newCorner.y, 712, accuracy: 1e-9)
    }

    func testSizeStaysInRange() {
        let start = shape(.circle, at: CGPoint(x: 512, y: 512), size: 200)
        XCTAssertEqual(ShapeEditing.resized(start, by: 0.01).size, ShapeEditing.sizeRange.lowerBound)
        XCTAssertEqual(ShapeEditing.resized(start, by: 100).size, ShapeEditing.sizeRange.upperBound)
        XCTAssertEqual(ShapeEditing.scaled(start, handle: CGPoint(x: 412, y: 412), finger: start.center).size,
                       ShapeEditing.sizeRange.lowerBound, "a handle dragged onto the centre")
    }

    func testRotationSnapsToFifteenDegreeSteps() {
        let start = shape(.star, at: CGPoint(x: 512, y: 512))
        XCTAssertEqual(ShapeEditing.rotated(start, by: 11 * degree).rotation, 15 * degree, accuracy: 1e-9)
        XCTAssertEqual(ShapeEditing.rotated(start, by: 7 * degree).rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(ShapeEditing.rotated(start, by: -38 * degree).rotation, -45 * degree, accuracy: 1e-9)
        XCTAssertEqual(ShapeEditing.snappedRotation(350 * degree), -15 * degree, accuracy: 1e-9, "kept in (−180°, 180°]")
        XCTAssertEqual(ShapeEditing.snappedRotation(-180 * degree), .pi, accuracy: 1e-9)
        for raw in stride(from: -400.0, through: 400, by: 3.7) {
            let r = ShapeEditing.snappedRotation(raw * degree) / (15 * degree)
            XCTAssertEqual(r, r.rounded(), accuracy: 1e-9, "\(raw)° lands on a 15° step")
        }
    }

    func testTwoFingersMoveResizeAndTurnTogether() {
        let start = shape(.triangle, at: CGPoint(x: 300, y: 300), size: 200)
        let result = ShapeEditing.transformed(start, translation: CGPoint(x: 40, y: -20), scale: 1.5,
                                              rotation: 28 * degree, snapDistance: 0)
        XCTAssertEqual(result.shape.center, CGPoint(x: 340, y: 280))
        XCTAssertEqual(result.shape.size, 300, accuracy: 1e-9)
        XCTAssertEqual(result.shape.rotation, 30 * degree, accuracy: 1e-9)
        XCTAssertEqual(result.guides, SnapGuides())
    }

    // MARK: Snapping

    func testCentreSnapsToTheCanvasCentreLinesWithGuides() {
        let start = shape(.circle, at: CGPoint(x: 400, y: 700))
        let near = ShapeEditing.moved(start, by: CGPoint(x: 106, y: 0), snapDistance: 10)   // x 506
        XCTAssertEqual(near.shape.center, CGPoint(x: 512, y: 700))
        XCTAssertEqual(near.guides, SnapGuides(vertical: true, horizontal: false))

        let both = ShapeEditing.moved(start, by: CGPoint(x: 120, y: -195), snapDistance: 10)  // (520, 505)
        XCTAssertEqual(both.shape.center, CGPoint(x: 512, y: 512))
        XCTAssertEqual(both.guides, SnapGuides(vertical: true, horizontal: true))

        let far = ShapeEditing.moved(start, by: CGPoint(x: 101, y: 0), snapDistance: 10)    // x 501
        XCTAssertEqual(far.shape.center, CGPoint(x: 501, y: 700), "11 away: no snap")
        XCTAssertEqual(far.guides, SnapGuides())
    }

    /// The star's path bounds aren't centred on its `center` (its bottom points
    /// reach less far down than its top point), so it's the bounds that snap.
    func testStarSnapsByItsPathBoundsNotItsBox() {
        let start = shape(.star, at: CGPoint(x: 300, y: 300), size: 400)        // outer radius 200
        let lift = 200 * (1 - starBottom) / 2                                    // bounds centre is this far above `center`
        // Centre lands on (510, 525): bounds centre (510, ≈505.9), within 10 of both lines.
        let result = ShapeEditing.moved(start, by: CGPoint(x: 210, y: 225), snapDistance: 10)
        let bounds = ShapeEditing.bounds(of: result.shape)
        XCTAssertEqual(bounds.midX, 512, accuracy: 1e-9)
        XCTAssertEqual(bounds.midY, 512, accuracy: 1e-9)
        XCTAssertEqual(result.shape.center.y, 512 + lift, accuracy: 1e-9)
        XCTAssertEqual(result.guides, SnapGuides(vertical: true, horizontal: true))
    }

    // MARK: Hit testing on real path bounds

    func testStarHitTestUsesPathBoundsNotTheSizeBox() throws {
        let star = shape(.star, at: CGPoint(x: 512, y: 512), size: 400)        // box 312…712
        let bounds = ShapeEditing.bounds(of: star)
        XCTAssertLessThan(bounds.width, 400, "a regular star is narrower than its box")
        XCTAssertEqual(bounds.maxY, 512 + 200 * starBottom, accuracy: 1e-9)

        // Between the star's arms, inside its path bounds: picks the star.
        let gap = CGPoint(x: 512 + 160 * cos(-54 * degree), y: 512 + 160 * sin(-54 * degree))
        XCTAssertFalse(ShapeGeometry.path(for: star).contains(gap), "the point really is between the arms")
        XCTAssertEqual(ShapeEditing.hitTest(gap, in: [star]), star.id)

        // Inside the size box but below the path bounds: misses.
        let belowBounds = CGPoint(x: 512, y: bounds.maxY + 15)
        XCTAssertLessThan(belowBounds.y, 712)
        XCTAssertNil(ShapeEditing.hitTest(belowBounds, in: [star]))
        XCTAssertNil(ShapeEditing.hitTest(CGPoint(x: bounds.maxX + 10, y: 512), in: [star]))
        XCTAssertEqual(ShapeEditing.hitTest(CGPoint(x: bounds.maxX + 10, y: 512), in: [star], slop: 12), star.id,
                       "slop grows the bounds for fingers")

        // Handles sit on the path bounds, not the box.
        XCTAssertEqual(ShapeEditing.handles(of: star)[2], CGPoint(x: bounds.maxX, y: bounds.maxY))
    }

    func testOutlineBeatsBoundsAndTopmostWins() {
        let below = shape(.circle, at: CGPoint(x: 560, y: 400), size: 200)
        let star = shape(.star, at: CGPoint(x: 512, y: 512), size: 400)
        let gap = CGPoint(x: 512 + 160 * cos(-54 * degree), y: 512 + 160 * sin(-54 * degree))
        XCTAssertTrue(ShapeGeometry.path(for: below).contains(gap))
        XCTAssertEqual(ShapeEditing.hitTest(gap, in: [below, star]), below.id,
                       "in the star's gap, the circle underneath is really there")
        XCTAssertEqual(ShapeEditing.hitTest(CGPoint(x: 512, y: 512), in: [below, star]), star.id, "topmost")
        XCTAssertNil(ShapeEditing.hitTest(CGPoint(x: 50, y: 50), in: [below, star]))
    }

    // MARK: Flip

    func testFlipUpsideDownTurnsATriangleOver() {
        let triangle = shape(.triangle, at: CGPoint(x: 512, y: 512), size: 200)
        let flipped = ShapeEditing.flipped(triangle, sideways: false)
        XCTAssertEqual(flipped.rotation, .pi, accuracy: 1e-9)
        // Wide at the top now, pointed at the bottom: the opposite of upright.
        let nearTop = CGPoint(x: 440, y: 430), nearBottom = CGPoint(x: 440, y: 600)
        XCTAssertFalse(ShapeGeometry.path(for: triangle).contains(nearTop))
        XCTAssertTrue(ShapeGeometry.path(for: triangle).contains(nearBottom))
        XCTAssertTrue(ShapeGeometry.path(for: flipped).contains(nearTop))
        XCTAssertFalse(ShapeGeometry.path(for: flipped).contains(nearBottom))
        XCTAssertFalse(ShapeEditing.looksTheSame(triangle, flipped))
    }

    func testFlipSidewaysMirrorsTheRotation() {
        let turned = shape(.triangle, at: CGPoint(x: 512, y: 512), rotation: 30 * degree)
        XCTAssertEqual(ShapeEditing.flipped(turned, sideways: true).rotation, -30 * degree, accuracy: 1e-9)
        XCTAssertEqual(ShapeEditing.flipped(turned, sideways: false).rotation, 150 * degree, accuracy: 1e-9)
    }

    func testFlipsThatChangeNothingAreRecognised() {
        let upright = shape(.triangle, at: CGPoint(x: 512, y: 512))
        XCTAssertTrue(ShapeEditing.looksTheSame(upright, ShapeEditing.flipped(upright, sideways: true)))
        let circle = shape(.circle, at: CGPoint(x: 512, y: 512), rotation: 0.4)
        XCTAssertTrue(ShapeEditing.looksTheSame(circle, ShapeEditing.flipped(circle, sideways: false)))
        let square = shape(.roundedSquare, at: CGPoint(x: 512, y: 512))
        XCTAssertTrue(ShapeEditing.looksTheSame(square, ShapeEditing.flipped(square, sideways: false)))
        let star = shape(.star, at: CGPoint(x: 512, y: 512))
        XCTAssertFalse(ShapeEditing.looksTheSame(star, ShapeEditing.flipped(star, sideways: false)), "points down")
        XCTAssertTrue(ShapeEditing.looksTheSame(star, ShapeEditing.flipped(star, sideways: true)))
    }
}
