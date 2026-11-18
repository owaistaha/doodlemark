import PencilKit
import XCTest
@testable import Doodlemark

@MainActor
final class StrokeSmootherTests: XCTestCase {
    /// The rendered centre line, in canvas space.
    private func rendered(_ stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(stroke.transform) }
    }

    /// Mean absolute turn between consecutive 2 pt steps, in radians.
    private func meanTurn(_ points: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0
        var count = 0
        for i in 1..<(points.count - 1) {
            let a = atan2(points[i].y - points[i - 1].y, points[i].x - points[i - 1].x)
            let b = atan2(points[i + 1].y - points[i].y, points[i + 1].x - points[i].x)
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            total += abs(d)
            count += 1
        }
        return total / CGFloat(count)
    }

    func testSmoothingLowersTheMeanTurningAngleOfAWobblyStroke() {
        let wobbly = GateFixtures.wobbly
        let before = meanTurn(rendered(wobbly))
        let after = meanTurn(rendered(StrokeSmoother.smoothed(wobbly)))
        print("SMOOTH| wobbly mean turn \(before) → \(after) rad")
        XCTAssertLessThan(after, before * 0.8, "smoothing should take out a good part of the wobble")
    }

    func testEndpointsStayWithinHalfAPoint() {
        for stroke in [GateFixtures.wobbly, GateFixtures.arc, GateFixtures.zigzag, GateFixtures.transformed] {
            let before = rendered(stroke)
            let after = rendered(StrokeSmoother.smoothed(stroke))
            XCTAssertLessThanOrEqual(hypot(after[0].x - before[0].x, after[0].y - before[0].y), 0.5)
            XCTAssertLessThanOrEqual(hypot(after.last!.x - before.last!.x, after.last!.y - before.last!.y), 0.5)
        }
    }

    func testZigzagCornersStaySharp() {
        let corners = [CGPoint(x: 260, y: 300), CGPoint(x: 400, y: 640), CGPoint(x: 540, y: 300),
                       CGPoint(x: 680, y: 640), CGPoint(x: 820, y: 300)]
        let control = StrokeSmoother.smoothed(GateFixtures.zigzag).path.map(\.location)
        for corner in corners {
            XCTAssertTrue(control.contains(corner), "corner \(corner) must stay exactly where it was")
        }
        // And the rendered line reaches into each corner as far as the raw one does.
        let before = rendered(GateFixtures.zigzag)
        let after = rendered(StrokeSmoother.smoothed(GateFixtures.zigzag))
        for corner in corners {
            let raw = before.map { hypot($0.x - corner.x, $0.y - corner.y) }.min()!
            let smoothed = after.map { hypot($0.x - corner.x, $0.y - corner.y) }.min()!
            XCTAssertLessThanOrEqual(smoothed, raw + 0.25, "corner \(corner) rounded off (raw \(raw))")
        }
    }

    func testStraightLinesDontMove() {
        let line = GateFixtures.diagonal
        XCTAssertEqual(StrokeSmoother.smoothed(line).path.map(\.location).count, line.path.count)
        for (a, b) in zip(StrokeSmoother.smoothed(line).path.map(\.location), line.path.map(\.location)) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        }
    }

    func testDotsAreUntouched() {
        for dot in GateFixtures.dots {
            XCTAssertEqual(StrokeSmoother.smoothed(dot).path.map(\.location), dot.path.map(\.location))
        }
    }

    func testOnlyLocationsChange() {
        let stroke = GateFixtures.wobbly
        let smoothed = StrokeSmoother.smoothed(stroke)
        XCTAssertEqual(smoothed.path.count, stroke.path.count)
        XCTAssertEqual(smoothed.path.map(\.size), stroke.path.map(\.size))
        XCTAssertEqual(smoothed.path.map(\.timeOffset), stroke.path.map(\.timeOffset))
        XCTAssertEqual(smoothed.path.creationDate, stroke.path.creationDate)
        XCTAssertEqual(smoothed.transform, stroke.transform)
        XCTAssertEqual(smoothed.ink.inkType, .monoline)
    }
}
