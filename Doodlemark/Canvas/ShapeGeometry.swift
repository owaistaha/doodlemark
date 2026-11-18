import CoreGraphics
import Foundation

/// The single source of truth for shape outlines. The on-screen Shapes layer
/// and the SVG exporter both call this. Never draw a shape any other way.
///
/// Every shape is built in a `size × size` box centered on `center`, then
/// rotated around `center` (positive = clockwise on screen, since y points down).
///
/// - circle: fills the box (diameter = size).
/// - roundedSquare: fills the box, corner radius = `roundedSquareCornerRatio × size`.
/// - triangle: apex at top-center, base along the bottom edge; fills the box.
/// - star: regular 5-point star, point up, outer radius = size / 2, centered on
///   `center`. Its bounds are slightly smaller than the box (a regular star isn't square).
enum ShapeGeometry {
    static let roundedSquareCornerRatio: CGFloat = 0.2
    /// Inner/outer radius of the classic regular pentagram (sin 18° / sin 54°).
    static let starInnerRatio: CGFloat = sin(.pi / 10) / sin(3 * .pi / 10)

    static func path(for shape: LogoShape) -> CGPath {
        path(kind: shape.kind, center: shape.center, size: shape.size, rotation: shape.rotation)
    }

    static func path(kind: LogoShape.Kind, center: CGPoint, size: CGFloat, rotation: Double) -> CGPath {
        let local = unitPath(kind: kind, size: size)   // centered on (0, 0)
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(rotation))
        return local.copy(using: &transform) ?? local
    }

    /// The unrotated shape centered on the origin.
    private static func unitPath(kind: LogoShape.Kind, size: CGFloat) -> CGPath {
        let half = size / 2
        let box = CGRect(x: -half, y: -half, width: size, height: size)

        switch kind {
        case .circle:
            return CGPath(ellipseIn: box, transform: nil)

        case .roundedSquare:
            let radius = size * roundedSquareCornerRatio
            return CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -half))       // apex
            path.addLine(to: CGPoint(x: half, y: half))  // bottom right
            path.addLine(to: CGPoint(x: -half, y: half)) // bottom left
            path.closeSubpath()
            return path

        case .star:
            let outer = half
            let inner = outer * starInnerRatio
            let path = CGMutablePath()
            for i in 0..<10 {
                let radius = i.isMultiple(of: 2) ? outer : inner
                // Start straight up (-90°) and step 36° clockwise.
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }
}
