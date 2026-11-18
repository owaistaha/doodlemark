import XCTest
@testable import Doodlemark

/// The single geometry function: size, centering and rotation for all four kinds.
final class ShapeGeometryTests: XCTestCase {
    private let center = CGPoint(x: 400, y: 600)
    private let size: CGFloat = 200
    private let accuracy: CGFloat = 0.01

    private func bounds(_ kind: LogoShape.Kind, rotation: Double = 0) -> CGRect {
        ShapeGeometry.path(kind: kind, center: center, size: size, rotation: rotation).boundingBoxOfPath
    }

    func testCircleSquareAndTriangleFillTheirBox() {
        let box = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        for kind in [LogoShape.Kind.circle, .roundedSquare, .triangle] {
            let b = bounds(kind)
            XCTAssertEqual(b.minX, box.minX, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(b.minY, box.minY, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(b.width, box.width, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(b.height, box.height, accuracy: accuracy, "\(kind)")
        }
    }

    func testStarIsRegularPointUpAndInsideItsBox() {
        let b = bounds(.star)
        let outer = size / 2
        // Top point touches the top of the box; the width is 2·R·sin(72°).
        XCTAssertEqual(b.minY, center.y - outer, accuracy: accuracy)
        XCTAssertEqual(b.width, 2 * outer * sin(2 * .pi / 5), accuracy: accuracy)
        // Bottom points sit at R·cos(36°) below the center.
        XCTAssertEqual(b.maxY, center.y + outer * cos(.pi / 5), accuracy: accuracy)
    }

    func testEveryKindIsHorizontallyCenteredAndNonEmpty() {
        for kind in LogoShape.Kind.allCases {
            let b = bounds(kind)
            XCTAssertFalse(b.isEmpty, "\(kind)")
            XCTAssertEqual(b.midX, center.x, accuracy: accuracy, "\(kind)")
        }
    }

    func testRotationTurnsAroundTheCenterForEveryKind() {
        // Rotating by θ must equal rotating the unrotated path around `center`.
        let angle = 0.7
        for kind in LogoShape.Kind.allCases {
            let rotated = ShapeGeometry.path(kind: kind, center: center, size: size, rotation: angle)
            var aroundCenter = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y)
            let expected = ShapeGeometry.path(kind: kind, center: center, size: size, rotation: 0)
                .copy(using: &aroundCenter)!
            let a = rotated.boundingBoxOfPath, e = expected.boundingBoxOfPath
            XCTAssertEqual(a.minX, e.minX, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(a.minY, e.minY, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(a.maxX, e.maxX, accuracy: accuracy, "\(kind)")
            XCTAssertEqual(a.maxY, e.maxY, accuracy: accuracy, "\(kind)")
        }
    }

    func testPositiveRotationIsClockwiseOnScreen() {
        // Triangle apex is up. A quarter turn clockwise (y down) points it right.
        let probe = CGPoint(x: center.x + 0.45 * size, y: center.y)
        let upright = ShapeGeometry.path(kind: .triangle, center: center, size: size, rotation: 0)
        let turned = ShapeGeometry.path(kind: .triangle, center: center, size: size, rotation: .pi / 2)
        XCTAssertFalse(upright.contains(probe))
        XCTAssertTrue(turned.contains(probe))
    }

    func testRotatedSquareGetsWiderBounds() {
        XCTAssertGreaterThan(bounds(.roundedSquare, rotation: .pi / 4).width, size * 1.2)
    }

    func testPathForShapeUsesItsFields() {
        let shape = LogoShape(id: UUID(), kind: .circle, center: center, size: size, rotation: 0, fill: Fixtures.ink)
        XCTAssertEqual(ShapeGeometry.path(for: shape).boundingBoxOfPath, bounds(.circle))
    }
}
