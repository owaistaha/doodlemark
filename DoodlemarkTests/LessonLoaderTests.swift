import PencilKit
import XCTest
@testable import Doodlemark

/// The five bundled lessons: they load, follow the format rules, and their
/// own targets are 3-star strokes. Plus a fairness check of the scoring
/// thresholds with simulated finger strokes.
final class LessonLoaderTests: XCTestCase {
    func testEveryLessonParsesInOrder() throws {
        let lessons = LessonLibrary.all()
        XCTAssertEqual(lessons.map(\.id), ["rocket", "bolt-shield", "star-club", "cat-badge", "moon-cafe"])
        XCTAssertEqual(lessons.map(\.title), ["Rocket in 5 strokes", "Lightning shield", "Star club badge",
                                              "Cat face badge", "Moon café"])
        XCTAssertEqual(lessons.map(\.levelName), ["Easy", "Easy", "Easy", "Medium", "Medium"], "easy → harder")
        for id in LessonLibrary.ids {
            XCTAssertNoThrow(try LessonLibrary.load(id), id)    // the throwing path, with the reason on failure
        }
        for lesson in lessons {
            XCTAssertTrue((4...8).contains(lesson.steps.count), lesson.id)
            XCTAssertEqual(lesson.palette.count, 3, lesson.id)
            XCTAssertFalse(lesson.inkSteps.isEmpty, lesson.id)
        }
        XCTAssertEqual(lessons.first { $0.id == "rocket" }?.steps.count, 5, "Rocket in 5 strokes")
    }

    func testAllPointsAreInsideTheCanvas() {
        for lesson in LessonLibrary.all() {
            for (index, step) in lesson.steps.enumerated() {
                for p in step.points ?? [] {
                    XCTAssertTrue((0...1024).contains(p.x) && (0...1024).contains(p.y), "\(lesson.id) step \(index + 1): \(p)")
                    if lesson.mirror { XCTAssertLessThanOrEqual(p.x, 512, "\(lesson.id): Mirror lessons draw the left half") }
                }
                if let shape = step.shape {
                    let r = shape.size / 2
                    XCTAssertTrue(shape.center.x - r >= 0 && shape.center.x + r <= 1024
                                  && shape.center.y - r >= 0 && shape.center.y + r <= 1024, "\(lesson.id) shape")
                }
            }
        }
    }

    func testEveryStepHasKidFriendlyWords() {
        for lesson in LessonLibrary.all() {
            for step in lesson.steps {
                for text in [step.name, step.tip, step.how] {
                    XCTAssertFalse(text.isEmpty)
                    XCTAssertFalse(text.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x2000 }, "no emoji: \(text)")
                    XCTAssertFalse(text.contains("!"), "no exclamation-mark spam: \(text)")
                }
                XCTAssertLessThanOrEqual(step.tip.count, 60, "one short line: \(step.tip)")
            }
        }
    }

    /// Every target, traced exactly, is 3 stars: as raw points, and drawn
    /// as a real PencilKit stroke read back the way the player will.
    func testEveryTargetScoresThreeStarsAgainstItself() {
        for lesson in LessonLibrary.all() {
            for (index, step) in lesson.steps.enumerated() where step.kind == .ink {
                let target = step.points!
                let label = "\(lesson.id) step \(index + 1) \(step.name)"
                XCTAssertEqual(StrokeScorer.score(target, target: target).stars, 3, label)

                let stroke = Fixtures.monolineStroke(GateFixtures.densified(target), width: step.width ?? 16)
                let score = StrokeScorer.score(StrokeScorer.points(of: stroke), target: target)
                XCTAssertEqual(score.stars, 3, "\(label): \(score)")
                XCTAssertEqual(score.problem, .none, "\(label): \(score)")
            }
        }
    }

    func testTheValidatorCatchesBadLessons() throws {
        var lesson = try LessonLibrary.load("rocket")
        lesson.steps[1].points = [CGPoint(x: 500, y: 100), CGPoint(x: 1100, y: 100)]
        XCTAssertThrowsError(try LessonLibrary.validate(lesson), "outside the canvas")
        lesson = try LessonLibrary.load("rocket")
        lesson.steps[1].points = [CGPoint(x: 600, y: 100), CGPoint(x: 700, y: 300)]
        XCTAssertThrowsError(try LessonLibrary.validate(lesson), "right half in a Mirror lesson")
        lesson = try LessonLibrary.load("rocket")
        lesson.steps = Array(lesson.steps.prefix(3))
        XCTAssertThrowsError(try LessonLibrary.validate(lesson), "fewer than 4 steps")
        XCTAssertThrowsError(try LessonLibrary.load("no-such-lesson"))
    }

    // MARK: Fairness check (not a pass/fail on exact numbers)

    /// A finger-like trace of `target`: the gate's wobble (±1.5 pt every
    /// ~17 pt plus ±0.8 pt every ~7 pt, as in `GateFixtures.wobbly`) scaled
    /// by `shake`, plus a slow drift off the line of up to `drift` pt.
    /// Deterministic for a seed. Goes through a real PencilKit stroke.
    static func fingerTrace(_ target: [CGPoint], shake: Double, drift: Double, seed: Int) -> [CGPoint] {
        let length = StrokeScorer.length(of: target)
        let dense = StrokeScorer.resample(target, count: max(8, Int(length / 2)))
        let phase = Double(seed) * 1.7
        var traced: [CGPoint] = []
        var walked = 0.0
        for i in dense.indices {
            if i > 0 { walked += hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y) }
            let a = dense[max(0, i - 1)], b = dense[min(dense.count - 1, i + 1)]
            let tangent = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let size = max(1e-9, hypot(tangent.dx, tangent.dy))
            let normal = CGVector(dx: -tangent.dy / size, dy: tangent.dx / size)
            let offset = shake * (1.5 * sin(2 * .pi * walked / 17 + phase) + 0.8 * sin(2 * .pi * walked / 7 + 2 * phase))
                + drift * sin(.pi * walked / max(length, 1) * 1.3 + phase)
            traced.append(CGPoint(x: dense[i].x + normal.dx * offset, y: dense[i].y + normal.dy * offset))
        }
        let stroke = Fixtures.monolineStroke(traced, width: 16)
        return StrokeScorer.points(of: stroke)
    }

    static let fingers: [(name: String, shake: Double, drift: Double)] = [
        ("steady", 0.5, 4),
        ("gate wobble", 1, 0),
        ("typical", 1, 10),
        ("shaky", 2, 14),
        ("sloppy", 3, 30),
        ("way off", 2, 70),
    ]

    /// Reports the star spread per lesson and finger, and checks the
    /// thresholds are fair: a steady finger gets 3 stars, an ordinary one
    /// mostly 2–3, a sloppy one never 3, and nobody careful is told to redo.
    func testThresholdsAreFairToWobblyFingers() throws {
        var report = ["Learn scoring fairness: stars per traced step (5 seeds each), ScoringConfig.standard",
                      "finger: shake × gate wobble, drift pt", ""]
        var byFinger: [String: [Int]] = [:]
        var wobbles: [String: [Double]] = [:]
        var redoReasons: [String: [StrokeProblem: Int]] = [:]
        for lesson in LessonLibrary.all() {
            var row = lesson.id.padding(toLength: 12, withPad: " ", startingAt: 0)
            for finger in Self.fingers {
                var stars: [Int] = []
                for (index, step) in lesson.inkSteps.enumerated() {
                    for seed in 0..<5 {
                        let trace = Self.fingerTrace(step.points!, shake: finger.shake, drift: finger.drift,
                                                     seed: seed * 7 + index)
                        let score = StrokeScorer.score(trace, target: step.points!)
                        stars.append(score.stars)
                        wobbles[finger.name, default: []].append(score.wobble)
                        if score.stars == 0 { redoReasons[finger.name, default: [:]][score.problem, default: 0] += 1 }
                    }
                }
                byFinger[finger.name, default: []] += stars
                let histogram = (0...3).map { s in stars.filter { $0 == s }.count }
                row += " | \(finger.name): 3★\(histogram[3]) 2★\(histogram[2]) 1★\(histogram[1]) 0★\(histogram[0])"
            }
            report.append(row)
        }
        report.append("")
        for finger in Self.fingers {
            let stars = byFinger[finger.name]!
            let w = wobbles[finger.name]!.sorted()
            report.append(String(format: "%@ (shake %.1f, drift %.0f): mean %.2f★, 3★ %d%%, 0★ %d%%, wobble median %.3f max %.3f",
                                 finger.name, finger.shake, finger.drift,
                                 Double(stars.reduce(0, +)) / Double(stars.count),
                                 stars.filter { $0 == 3 }.count * 100 / stars.count,
                                 stars.filter { $0 == 0 }.count * 100 / stars.count,
                                 w[w.count / 2], w.last!))
            let reasons = redoReasons[finger.name] ?? [:]
            if !reasons.isEmpty {
                report.append("    redos say: " + reasons.sorted { $0.value > $1.value }
                    .map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", "))
            }
        }
        let text = report.joined(separator: "\n")
        print("CALIB|\n" + text)
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "GateOutput/learn-calibration.txt")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: out, atomically: true, encoding: .utf8)

        func share(_ finger: String, _ test: (Int) -> Bool) -> Double {
            let stars = byFinger[finger]!
            return Double(stars.filter(test).count) / Double(stars.count)
        }
        XCTAssertEqual(share("steady") { $0 == 3 }, 1, "a steady finger on the line always gets 3 stars")
        XCTAssertEqual(share("gate wobble") { $0 >= 2 }, 1, "the gate's shaky-finger wobble still gets 2+ stars")
        XCTAssertGreaterThanOrEqual(share("typical") { $0 >= 2 }, 0.8, "an ordinary finger mostly gets 2–3 stars")
        XCTAssertEqual(share("typical") { $0 == 0 }, 0, "and is never told to redo")
        XCTAssertEqual(share("sloppy") { $0 == 3 }, 0, "30 pt off the line is never 3 stars")
        XCTAssertGreaterThanOrEqual(share("way off") { $0 == 0 }, 0.8, "70 pt off is a redo")
        // A shaky line along the whole target is told it's off the line,
        // not that it's too long or short.
        for finger in ["sloppy", "way off"] {
            let reasons = redoReasons[finger] ?? [:]
            let total = reasons.values.reduce(0, +)
            let length = (reasons[.tooLong] ?? 0) + (reasons[.tooShort] ?? 0)
            XCTAssertLessThanOrEqual(Double(length), Double(total) * 0.2, "\(finger) redos: \(reasons)")
        }
    }
}
