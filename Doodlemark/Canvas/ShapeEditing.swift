import CoreGraphics
import Foundation

/// Which canvas-centre guides show while a moved shape is snapped to them.
struct SnapGuides: Equatable, Sendable {
    /// The vertical line x = 512 (the shape's centre is on it).
    var vertical = false
    /// The horizontal line y = 512.
    var horizontal = false
}

/// The maths behind moving, resizing, turning and flipping shapes. Pure
/// functions in canvas space (1024 × 1024), so the gestures stay thin and
/// everything here is unit-tested.
///
/// Selection handles, hit testing and snapping use the shape's **real path
/// bounds** (`ShapeGeometry.path(for:).boundingBoxOfPath`), never the
/// `size × size` box: a regular star is narrower than its box (TECH_SPEC).
enum ShapeEditing {
    static let canvasCenter = CGPoint(x: CanvasViewport.canvasSide / 2, y: CanvasViewport.canvasSide / 2)
    /// A new shape: centred, about a third of the canvas.
    static let newShapeSize: CGFloat = 320
    /// Smallest and largest `size`. Big enough to grab with a finger at
    /// "fits" zoom; large enough to fill the canvas as a background.
    static let sizeRange: ClosedRange<CGFloat> = 40...1400
    /// Rotation moves in 15° steps.
    static let rotationStep = Double.pi / 12

    // MARK: Bounds and hit testing

    static func bounds(of shape: LogoShape) -> CGRect {
        ShapeGeometry.path(for: shape).boundingBoxOfPath
    }

    /// The four corner handles: the corners of the path bounds.
    static func handles(of shape: LogoShape) -> [CGPoint] {
        let b = bounds(of: shape)
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
    }

    /// The shape a tap at `point` picks: the topmost whose outline contains
    /// it, else the topmost whose path bounds (grown by `slop`) contain it, so
    /// a tap between a star's arms still picks the star, but a shape lying
    /// underneath it wins where its own outline is.
    static func hitTest(_ point: CGPoint, in shapes: [LogoShape], slop: CGFloat = 0) -> LogoShape.ID? {
        if let inside = shapes.last(where: { ShapeGeometry.path(for: $0).contains(point) }) {
            return inside.id
        }
        return shapes.last { bounds(of: $0).insetBy(dx: -slop, dy: -slop).contains(point) }?.id
    }

    // MARK: Move

    /// `start` moved by `translation`. The centre of its path bounds snaps
    /// to x = 512 and/or y = 512 when within `snapDistance`, and the centre
    /// stays on the canvas so a shape can't be lost off the edge.
    static func moved(_ start: LogoShape, by translation: CGPoint,
                      snapDistance: CGFloat) -> (shape: LogoShape, guides: SnapGuides) {
        var shape = start
        let side = CanvasViewport.canvasSide
        shape.center = CGPoint(x: min(max(start.center.x + translation.x, 0), side),
                               y: min(max(start.center.y + translation.y, 0), side))
        return snapped(shape, snapDistance: snapDistance)
    }

    /// Snaps the centre of `shape`'s path bounds to the canvas centre lines.
    static func snapped(_ shape: LogoShape, snapDistance: CGFloat) -> (shape: LogoShape, guides: SnapGuides) {
        var result = shape
        var guides = SnapGuides()
        let b = bounds(of: shape)
        if abs(b.midX - canvasCenter.x) <= snapDistance {
            result.center.x += canvasCenter.x - b.midX
            guides.vertical = true
        }
        if abs(b.midY - canvasCenter.y) <= snapDistance {
            result.center.y += canvasCenter.y - b.midY
            guides.horizontal = true
        }
        return (result, guides)
    }

    // MARK: Resize

    /// Dragging a corner handle from `handle` to `finger`: the shape grows or
    /// shrinks around its centre with the finger's distance from the centre,
    /// so the corner stays under the finger (one finger is enough).
    static func scaled(_ start: LogoShape, handle: CGPoint, finger: CGPoint) -> LogoShape {
        let from = hypot(handle.x - start.center.x, handle.y - start.center.y)
        guard from > 0 else { return start }
        return resized(start, by: hypot(finger.x - start.center.x, finger.y - start.center.y) / from)
    }

    static func resized(_ start: LogoShape, by factor: CGFloat) -> LogoShape {
        var shape = start
        shape.size = min(max(start.size * factor, sizeRange.lowerBound), sizeRange.upperBound)
        return shape
    }

    // MARK: Rotate

    /// `start` turned by `angle` (radians, clockwise), in 15° steps.
    static func rotated(_ start: LogoShape, by angle: Double) -> LogoShape {
        var shape = start
        shape.rotation = snappedRotation(start.rotation + angle)
        return shape
    }

    /// The nearest 15° step, in (−180°, 180°].
    static func snappedRotation(_ rotation: Double) -> Double {
        normalized((rotation / rotationStep).rounded() * rotationStep)
    }

    /// The same angle in (−π, π].
    static func normalized(_ rotation: Double) -> Double {
        var r = rotation.truncatingRemainder(dividingBy: 2 * .pi)
        if r <= -.pi { r += 2 * .pi }
        if r > .pi { r -= 2 * .pi }
        return abs(r) < 1e-9 ? 0 : r
    }

    // MARK: Two fingers

    /// Two fingers on the selected shape: it follows the fingers' midpoint
    /// (`translation`), grows with the pinch (`scale`) and turns with them
    /// (`rotation`, in 15° steps), then snaps like a move.
    static func transformed(_ start: LogoShape, translation: CGPoint, scale: CGFloat, rotation: Double,
                            snapDistance: CGFloat) -> (shape: LogoShape, guides: SnapGuides) {
        let turned = rotated(resized(start, by: scale), by: rotation)
        return moved(turned, by: translation, snapDistance: snapDistance)
    }

    // MARK: Flip

    /// Mirrored left ↔ right (`sideways`) or top ↔ bottom, around its centre.
    /// All four kinds are mirror-symmetric about their own vertical axis, so
    /// a flip is a rotation: sideways r → −r, upside down r → π − r. No extra
    /// model field, and the one geometry function stays the only one.
    static func flipped(_ shape: LogoShape, sideways: Bool) -> LogoShape {
        var result = shape
        result.rotation = normalized(sideways ? -shape.rotation : .pi - shape.rotation)
        return result
    }

    /// True when two shapes draw exactly the same outline: same kind, centre
    /// and size, and rotations that differ by a whole symmetry turn of the
    /// kind (a flip button that wouldn't change anything is disabled).
    static func looksTheSame(_ a: LogoShape, _ b: LogoShape) -> Bool {
        guard a.kind == b.kind, a.center == b.center, a.size == b.size, a.fill == b.fill else { return false }
        let turn: Double
        switch a.kind {
        case .circle: return true
        case .roundedSquare: turn = .pi / 2
        case .star: turn = 2 * .pi / 5
        case .triangle: turn = 2 * .pi
        }
        let steps = (a.rotation - b.rotation) / turn
        return abs(steps - steps.rounded()) < 1e-9
    }
}

extension LogoShape.Kind {
    /// Name in the Shapes panel.
    var title: String {
        switch self {
        case .circle: "Circle"
        case .roundedSquare: "Rounded square"
        case .triangle: "Triangle"
        case .star: "Star"
        }
    }
}
