import PencilKit
import XCTest
@testable import Doodlemark

/// Learn scoring (TECH_SPEC "Stroke scoring"): deterministic maths only.
final class StrokeScorerTests: XCTestCase {
    /// A gentle curve, 600 pt long-ish, like a lesson stroke.
    static let curve: [CGPoint] = (0...40).map { i in
        let t = Double(i) / 40
        return CGPoint(x: 200 + 600 * t, y: 500 - 160 * sin(.pi * t))
    }
    static let straight = [CGPoint(x: 200, y: 500), CGPoint(x: 800, y: 500)]

    func testAnIdenticalStrokeGetsThreeStars() {
        let score = StrokeScorer.score(Self.curve, target: Self.curve)
        XCTAssertEqual(score.stars, 3)
        XCTAssertEqual(score.distance, 0, accuracy: 1e-9)
        XCTAssertEqual(score.wobble, 0, accuracy: 1e-9)
        XCTAssertEqual(score.lengthRatio, 1, accuracy: 1e-9)
        XCTAssertFalse(score.reversed)
        XCTAssertEqual(score.problem, .none)
        XCTAssertEqual(score.feedback.title, "Spot on")
    }

    func testAReversedStrokeGetsTheSameScore() {
        let forward = StrokeScorer.score(Self.curve, target: Self.curve)
        let backward = StrokeScorer.score(Self.curve.reversed(), target: Self.curve)
        XCTAssertEqual(backward.stars, forward.stars)
        XCTAssertEqual(backward.distance, forward.distance, accuracy: 1e-9)
        XCTAssertEqual(backward.wobble, forward.wobble, accuracy: 1e-9)
        XCTAssertTrue(backward.reversed)
        XCTAssertEqual(backward.problem, .direction, "no star off, just a tip about the dot")
        XCTAssertEqual(backward.feedback.tip, "Next time, try starting at the blue dot.")
    }

    func testShifted50PointsScoresLower() {
        let shifted = Self.curve.map { CGPoint(x: $0.x, y: $0.y + 50) }
        let score = StrokeScorer.score(shifted, target: Self.curve)
        XCTAssertEqual(score.distance, 50, accuracy: 0.5)
        XCTAssertLessThan(score.stars, 3)
        XCTAssertEqual(score.stars, 1, "36 < 50 ≤ 60")
        XCTAssertEqual(score.problem, .shape)

        // The star steps sit exactly on the TECH_SPEC thresholds.
        for (offset, stars) in [(17.0, 3), (19.0, 2), (35.0, 2), (37.0, 1), (59.0, 1), (61.0, 0)] {
            let moved = Self.straight.map { CGPoint(x: $0.x, y: $0.y + offset) }
            XCTAssertEqual(StrokeScorer.score(moved, target: Self.straight).stars, stars, "offset \(offset)")
        }
    }

    func testHalfTheLengthIsAMiss() {
        let half = Array(Self.curve.prefix(21))
        let score = StrokeScorer.score(half, target: Self.curve)
        XCTAssertEqual(score.lengthRatio, 0.5, accuracy: 0.05)
        XCTAssertEqual(score.stars, 0)
        XCTAssertEqual(score.problem, .tooShort)
        XCTAssertEqual(score.feedback.title, "Almost! Try once more")
        XCTAssertEqual(score.feedback.tip, "Try drawing the whole line, all the way to the end.")

        // Traced the line, then went back over it: that really is too long.
        let tooLong = Self.curve + Self.curve.reversed().map { CGPoint(x: $0.x, y: $0.y + 1) }
        let long = StrokeScorer.score(tooLong, target: Self.curve)
        XCTAssertEqual(long.problem, .tooLong)
        XCTAssertEqual(long.stars, 0)
        XCTAssertEqual(long.feedback.tip, "Stop when you reach the end of the dashed line.")
        XCTAssertEqual(StrokeScorer.score([CGPoint(x: 300, y: 300)], target: Self.curve).problem, .tooShort, "a tap")
    }

    /// A zig-zag right on top of a straight target: the shape is fine, the
    /// line isn't. One star off and the wobble tip.
    func testAZigZagOverAStraightTargetGetsTheWobbleTip() {
        let zigzag = (0...50).map { i in CGPoint(x: 200 + 12 * Double(i), y: 500 + (i.isMultiple(of: 2) ? -5 : 5)) }
        let score = StrokeScorer.score(zigzag, target: Self.straight)
        XCTAssertLessThanOrEqual(score.distance, ScoringConfig.standard.threeStarDistance, "on the line")
        XCTAssertGreaterThan(score.wobble, ScoringConfig.standard.wobbleLimit)
        XCTAssertEqual(score.stars, 2)
        XCTAssertEqual(score.problem, .wobble)
        XCTAssertEqual(score.feedback.title, "Nice shape!")
        XCTAssertEqual(score.feedback.tip, "Your line is a bit wobbly. Try going a little slower for 3 stars.")
    }

    /// A big zig-zag along a short line is long, but the tip says what's
    /// really wrong: wobble, not "too long".
    func testAShakyLongStrokeIsToldItsWobbly() {
        let target = [CGPoint(x: 400, y: 500), CGPoint(x: 470, y: 500)]
        let zigzag = (0...9).map { i in CGPoint(x: 400 + 70 * Double(i) / 9, y: 500 + (i.isMultiple(of: 2) ? -16 : 16)) }
        let score = StrokeScorer.score(zigzag, target: target)
        XCTAssertGreaterThan(score.lengthRatio, 1.5)
        XCTAssertEqual(score.stars, 0)
        XCTAssertEqual(score.problem, .wobble)
        XCTAssertEqual(score.feedback.tip, "Your line got very wobbly. Go slowly and stay on the dashed line.")

        // And a long line somewhere else entirely is "off the line".
        let elsewhere = [CGPoint(x: 100, y: 900), CGPoint(x: 300, y: 950)]
        XCTAssertEqual(StrokeScorer.score(elsewhere, target: target).problem, .shape)

        // Drawing on past the end, straight, is "too long".
        let overshoot = [CGPoint(x: 400, y: 500), CGPoint(x: 600, y: 500)]
        XCTAssertEqual(StrokeScorer.score(overshoot, target: target).problem, .tooLong)
        XCTAssertEqual(StrokeScorer.score(overshoot.reversed(), target: target).problem, .shape, "the head doesn't match")
    }

    /// Wobble never makes a stroke a redo on its own.
    func testWobbleNeverDropsBelowOneStar() {
        let zigzag = (0...50).map { i in CGPoint(x: 200 + 12 * Double(i), y: 545 + (i.isMultiple(of: 2) ? -5 : 5)) }
        let score = StrokeScorer.score(zigzag, target: Self.straight)
        XCTAssertGreaterThan(score.distance, 36)
        XCTAssertEqual(score.stars, 1)
    }

    /// A target's own corners aren't wobble: tracing a zig-zag target exactly is 3 stars.
    func testCornersInTheTargetArentWobble() {
        let bolt = [CGPoint(x: 560, y: 290), CGPoint(x: 440, y: 540), CGPoint(x: 540, y: 540), CGPoint(x: 470, y: 760)]
        let traced = StrokeScorer.resample(bolt, count: 200)
        let score = StrokeScorer.score(traced, target: bolt)
        XCTAssertEqual(score.stars, 3)
        XCTAssertLessThan(score.wobble, 0.01)
    }

    func testTheSameStrokeAlwaysGetsTheSameScore() {
        let stroke = Fixtures.monolineStroke(GateFixtures.densified(Self.curve), width: 16)
        let first = StrokeScorer.score(StrokeScorer.points(of: stroke), target: Self.curve)
        for _ in 0..<50 {
            let again = Fixtures.monolineStroke(GateFixtures.densified(Self.curve), width: 16)
            XCTAssertEqual(StrokeScorer.score(StrokeScorer.points(of: again), target: Self.curve), first)
        }
        XCTAssertEqual(first.stars, 3)
    }

    /// Strokes are read with `stroke.transform` applied (a lasso-moved stroke).
    func testTheStrokeTransformIsApplied() {
        let moved = Self.curve.map { CGPoint(x: $0.x - 100, y: $0.y - 40) }
        let stroke = Fixtures.monolineStroke(GateFixtures.densified(moved), width: 16,
                                             transform: CGAffineTransform(translationX: 100, y: 40))
        let score = StrokeScorer.score(StrokeScorer.points(of: stroke), target: Self.curve)
        XCTAssertEqual(score.stars, 3)
        XCTAssertLessThan(score.distance, 2)
    }

    // MARK: Building blocks

    func testResampleSpacesPointsEvenly() {
        let points = StrokeScorer.resample([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 26)], count: 64)
        XCTAssertEqual(points.count, 64)
        XCTAssertEqual(points.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(points.last, CGPoint(x: 100, y: 26))
        let gaps = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        for gap in gaps where abs(gap - 2) > 0.3 {            // 126 / 63 = 2; the corner shortcut is shorter
            XCTAssertLessThan(gap, 2, "only the one corner shortcut")
        }
    }

    func testFrechetOfParallelLinesIsTheirGap() {
        let a = StrokeScorer.resample(Self.straight, count: 64)
        let b = a.map { CGPoint(x: $0.x, y: $0.y + 25) }
        XCTAssertEqual(StrokeScorer.frechetDistance(a, b), 25, accuracy: 1e-9)
        XCTAssertEqual(StrokeScorer.frechetDistance(a, a.reversed()), 600, accuracy: 1e-9, "walkers only go forwards")
    }

    func testNoFeedbackEverSaysFailed() {
        let problems: [StrokeProblem] = [.none, .shape, .direction, .tooShort, .tooLong, .wobble]
        for stars in 0...3 {
            for problem in problems {
                let feedback = StrokeFeedback(stars: stars, problem: problem)
                let words = (feedback.title + " " + feedback.tip).lowercased()
                XCTAssertFalse(words.contains("fail") || words.contains("wrong") || words.contains("bad"), words)
                if stars == 0 { XCTAssertEqual(feedback.title, "Almost! Try once more") }
            }
        }
    }
}
