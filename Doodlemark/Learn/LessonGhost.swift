import PencilKit
import UIKit

/// What the lesson player shows on the canvas (TECH_SPEC "Lesson player"):
/// the current step's target dashed in pencil blue, the steps still to
/// come faint, and the start dot with an arrow. Finished steps aren't
/// ghosted: they're real Ink strokes and placed shapes by then.
/// All in 1024 canvas space.
struct LessonGhost: Equatable {
    enum Mark: Equatable {
        case line([CGPoint])
        case shape(LessonShape)
    }

    /// The step to do now (and its mirrored copy in a Mirror lesson).
    var current: [Mark]
    /// Where to start and which way to go (ink steps).
    var start: CGPoint?
    var direction: CGVector?
    /// Later steps, faint.
    var upcoming: [Mark]

    init(lesson: Lesson, step index: Int) {
        func marks(_ step: LessonStep) -> [Mark] {
            switch step.kind {
            case .ink:
                let points = step.points ?? []
                return lesson.mirror ? [.line(points), .line(LessonInk.mirrored(points))] : [.line(points)]
            case .shape:
                return step.shape.map { [.shape($0)] } ?? []
            }
        }
        let steps = lesson.steps
        current = steps.indices.contains(index) ? marks(steps[index]) : []
        upcoming = steps.indices.contains(index) ? steps[(index + 1)...].flatMap(marks) : []
        if steps.indices.contains(index), steps[index].kind == .ink, let points = steps[index].points, points.count >= 2 {
            start = points[0]
            // The first bit of the line that's long enough to point along.
            let ahead = points.dropFirst().first { hypot($0.x - points[0].x, $0.y - points[0].y) > 4 } ?? points[1]
            direction = CGVector(dx: ahead.x - points[0].x, dy: ahead.y - points[0].y)
        }
    }

    /// A mark's outline in canvas space (shapes come from `ShapeGeometry`, the
    /// one source of shape outlines).
    static func path(_ mark: Mark) -> CGPath {
        switch mark {
        case .line(let points):
            let path = CGMutablePath()
            path.addLines(between: points)
            return path
        case .shape(let shape):
            return ShapeGeometry.path(kind: shape.kind, center: shape.center, size: shape.size, rotation: shape.rotation)
        }
    }
}

/// Lesson targets as Ink strokes: what "Skip this step" draws in, and what
/// tests and the sample progress trace with.
enum LessonInk {
    /// x ↦ 2·axis − x, for a Mirror lesson's other half.
    static func mirrored(_ points: [CGPoint]) -> [CGPoint] {
        points.map { CGPoint(x: 2 * Symmetry.axisX - $0.x, y: $0.y) }
    }

    /// A monoline stroke along `points`, `size` thick (the Line size), in
    /// `color`, built like a finger stroke: control points every 4 canvas
    /// points so PencilKit's spline stays on the line.
    static func stroke(along points: [CGPoint], size: CGFloat, color: HexColor) -> PKStroke {
        let dense = StrokeScorer.resample(points, count: max(2, Int(StrokeScorer.length(of: points) / 4) + 1))
        let width = LineSize.storedWidth(forSize: size)
        let controlPoints = dense.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.008,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.monoline, color: UIColor(cgColor: color.cgColor)),
                        path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    /// A step's target drawn in, plus its mirrored copy in a Mirror lesson
    /// (made the same way Mirror makes it on the canvas).
    static func strokes(for step: LessonStep, in lesson: Lesson, color: HexColor) -> [PKStroke] {
        guard step.kind == .ink, let points = step.points else { return [] }
        let stroke = stroke(along: points, size: step.width ?? LineSize.defaultSize, color: color)
        return lesson.mirror ? [stroke, Symmetry.mirrored(stroke)] : [stroke]
    }
}

/// Draws a `LessonGhost` over the canvas in view space, so dashes, the dot
/// and the arrow keep their size at any zoom. On screen only, never exported.
final class LessonGhostView: UIView {
    static let currentWidth: CGFloat = 4
    static let upcomingWidth: CGFloat = 3
    static let currentDash: [CGFloat] = [12, 9]
    static let upcomingDash: [CGFloat] = [8, 8]
    static let upcomingAlpha: CGFloat = 0.25
    static let dotRadius: CGFloat = 13
    static let dotRing: CGFloat = 3
    /// The arrow sits this far from the dot's centre, along the line.
    static let arrowDistance: CGFloat = 34
    static let arrowSize: CGFloat = 14

    var viewport = CanvasViewport(zoom: 1, offset: .zero) { didSet { setNeedsDisplay() } }
    var ghost: LessonGhost? { didSet { if ghost != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let ghost, let cg = UIGraphicsGetCurrentContext() else { return }
        var toView = CGAffineTransform(a: viewport.zoom, b: 0, c: 0, d: viewport.zoom,
                                       tx: -viewport.offset.x, ty: -viewport.offset.y)
        let blue = UIColor(Theme.pencilBlue)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        func stroke(_ marks: [LessonGhost.Mark], color: UIColor, width: CGFloat, dash: [CGFloat]) {
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(width)
            cg.setLineDash(phase: 0, lengths: dash)
            for mark in marks {
                guard let path = LessonGhost.path(mark).copy(using: &toView) else { continue }
                cg.addPath(path)
                cg.strokePath()
            }
        }
        stroke(ghost.upcoming, color: blue.withAlphaComponent(Self.upcomingAlpha),
               width: Self.upcomingWidth, dash: Self.upcomingDash)
        stroke(ghost.current, color: blue, width: Self.currentWidth, dash: Self.currentDash)
        cg.setLineDash(phase: 0, lengths: [])

        guard let start = ghost.start else { return }
        let dot = viewport.toView(start)
        if let direction = ghost.direction {
            let length = max(hypot(direction.dx, direction.dy), 1e-9)
            let u = CGVector(dx: direction.dx / length, dy: direction.dy / length)
            let tip = CGPoint(x: dot.x + u.dx * (Self.arrowDistance + Self.arrowSize / 2),
                              y: dot.y + u.dy * (Self.arrowDistance + Self.arrowSize / 2))
            let back = CGPoint(x: tip.x - u.dx * Self.arrowSize, y: tip.y - u.dy * Self.arrowSize)
            let half = Self.arrowSize * 0.6
            cg.move(to: tip)
            cg.addLine(to: CGPoint(x: back.x - u.dy * half, y: back.y + u.dx * half))
            cg.addLine(to: CGPoint(x: back.x + u.dy * half, y: back.y - u.dx * half))
            cg.closePath()
            cg.setFillColor(blue.cgColor)
            cg.fillPath()
        }
        let r = Self.dotRadius
        cg.setFillColor(UIColor(Theme.surface).cgColor)
        cg.fillEllipse(in: CGRect(x: dot.x - r - Self.dotRing, y: dot.y - r - Self.dotRing,
                                  width: 2 * (r + Self.dotRing), height: 2 * (r + Self.dotRing)))
        cg.setFillColor(blue.cgColor)
        cg.fillEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r))
    }
}
