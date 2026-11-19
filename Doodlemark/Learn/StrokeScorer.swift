import CoreGraphics
import PencilKit

/// What went most wrong with a traced stroke; picks the tip.
enum StrokeProblem: String, Equatable, Sendable {
    case none
    /// Off the dashed line.
    case shape
    /// Good line, drawn from the other end. Costs nothing; the tip mentions the dot.
    case direction
    case tooShort
    case tooLong
    /// Right shape, shaky line: one star off.
    case wobble
}

/// The result of scoring one stroke against one lesson step.
struct StrokeScore: Equatable, Sendable {
    /// 0...3. Zero means "Almost! Try once more", never "failed".
    var stars: Int
    /// Discrete Fréchet distance to the target (the better direction), canvas points.
    var distance: Double
    /// Extra mean turning over the target's, radians (0 = as smooth as the target).
    var wobble: Double
    /// User length / target length.
    var lengthRatio: Double
    /// The user went from the target's end to its start.
    var reversed: Bool
    var problem: StrokeProblem

    var feedback: StrokeFeedback { StrokeFeedback(stars: stars, problem: problem) }
}

/// Learn mode's stroke scoring (TECH_SPEC "Stroke scoring"): pure maths,
/// no UI, no randomness. The same stroke always gets the same score.
///
/// 1. Resample the user's stroke and the target to N points along their length.
/// 2. Compare with the target both ways round and keep the better one.
/// 3. Shape = discrete Fréchet distance between the resampled polylines.
/// 4. Wobble = the user's mean absolute turning angle minus the target's
///    (so a corner the target has isn't counted as wobble).
/// 5. Length ratio outside 0.6–1.5 is a miss. Both lengths are measured on
///    lines resampled with points at least 8 pt apart, so jitter isn't length.
///    A too-long miss says "too long" only if the stroke, cut where it comes
///    closest to the target's end, is a right-length 3-star trace; otherwise
///    the tip names the real problem (off the line, wobble).
/// 6. Stars from the distance; wobble takes one off (never below 1).
///
/// It scores the RAW stroke: the lesson player must pass the stroke from
/// before "Smooth my lines", which would hide exactly the wobble this measures.
enum StrokeScorer {
    static func score(_ user: [CGPoint], target: [CGPoint], config: ScoringConfig = .standard) -> StrokeScore {
        let n = config.sampleCount
        let u = resample(user, count: n)
        let t = resample(target, count: n)
        // Lengths are measured on coarser resampled lines (points at least
        // `lengthSampleSpacing` apart, at most N of them): wiggles finer
        // than that are wobble, not extra length, even on a short stroke
        // (a shaky line along the whole target isn't "too long").
        let lengthCount = max(2, min(n, Int((length(of: target) / config.lengthSampleSpacing).rounded(.up)) + 1))
        let coarseUser = resample(user, count: lengthCount)
        let targetLength = length(of: resample(target, count: lengthCount))
        let ratio = targetLength > 0 ? length(of: coarseUser) / targetLength : 0
        guard user.count >= 2, ratio >= config.lengthRatio.lowerBound else {
            return StrokeScore(stars: 0, distance: .infinity, wobble: 0, lengthRatio: ratio, reversed: false,
                               problem: .tooShort)
        }

        let forward = frechetDistance(u, t)
        let backward = frechetDistance(u, t.reversed())
        // Ties go to forward, so a symmetric target never claims "reversed".
        let reversed = backward < forward
        let distance = min(forward, backward)
        let wobble = max(0, meanTurning(u) - meanTurning(t))

        if ratio > config.lengthRatio.upperBound {
            // A miss either way. The tip says "too long" only if the stroke
            // really traced the line and kept going: cut it where it comes
            // closest to the target's end (its start, if drawn backwards) and
            // that head is the right length and a 3-star match. A long
            // zig-zag or a line far off the target is told what's really wrong.
            func tracedThenKeptGoing(_ head: [CGPoint], _ goal: [CGPoint]) -> Bool {
                let headLength = length(of: resample(head, count: lengthCount))
                return config.lengthRatio.contains(headLength / targetLength)
                    && frechetDistance(resample(head, count: n), goal) <= config.threeStarDistance
            }
            let kept = tracedThenKeptGoing(self.head(of: user, endingNear: target[target.count - 1]), t)
                || tracedThenKeptGoing(self.head(of: user, endingNear: target[0]), t.reversed())
            let problem: StrokeProblem = kept ? .tooLong
                : distance <= config.oneStarDistance && wobble > config.wobbleLimit ? .wobble : .shape
            return StrokeScore(stars: 0, distance: distance, wobble: wobble, lengthRatio: ratio,
                               reversed: reversed, problem: problem)
        }

        var stars: Int
        switch distance {
        case ...config.threeStarDistance: stars = 3
        case ...config.twoStarDistance: stars = 2
        case ...config.oneStarDistance: stars = 1
        default: stars = 0
        }
        let shaky = wobble > config.wobbleLimit
        if shaky, stars >= 2 { stars -= 1 }

        let problem: StrokeProblem
        if stars == 0 || distance > config.threeStarDistance {
            problem = .shape
        } else if shaky {
            problem = .wobble
        } else if reversed {
            problem = .direction
        } else {
            problem = .none
        }
        return StrokeScore(stars: stars, distance: distance, wobble: wobble, lengthRatio: ratio,
                           reversed: reversed, problem: problem)
    }

    /// A stroke's points in canvas space, `stroke.transform` applied
    /// (CLAUDE.md: always), sampled every 2 points along the path.
    static func points(of stroke: PKStroke) -> [CGPoint] {
        let path = stroke.path
        guard path.count > 1 else { return path.map { $0.location.applying(stroke.transform) } }
        return path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(stroke.transform) }
    }

    // MARK: Maths

    static func length(of points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// The stroke from its start up to the spot on it closest to `end`
    /// (on a segment, not only at a point).
    static func head(of points: [CGPoint], endingNear end: CGPoint) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var best = (index: 0, point: points[0], distance: distance(points[0], end))
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let squared = Double(ab.dx * ab.dx + ab.dy * ab.dy)
            let f = squared > 0 ? min(1, max(0, Double((end.x - a.x) * ab.dx + (end.y - a.y) * ab.dy) / squared)) : 0
            let p = CGPoint(x: a.x + ab.dx * f, y: a.y + ab.dy * f)
            let d = distance(p, end)
            if d < best.distance { best = (i, p, d) }
        }
        return Array(points[...best.index]) + [best.point]
    }

    /// `count` points evenly spaced along the polyline, first and last kept.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = points.first, count >= 2 else { return points }
        let total = length(of: points)
        guard total > 0 else { return Array(repeating: first, count: count) }
        let step = total / Double(count - 1)
        var result = [first]
        var segment = 0
        var walked = 0.0                                 // length up to points[segment]
        for i in 1..<(count - 1) {
            let goal = step * Double(i)
            while segment < points.count - 2,
                  walked + distance(points[segment], points[segment + 1]) < goal {
                walked += distance(points[segment], points[segment + 1])
                segment += 1
            }
            let a = points[segment], b = points[segment + 1]
            let piece = distance(a, b)
            let f = piece > 0 ? min(1, max(0, (goal - walked) / piece)) : 0
            result.append(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
        result.append(points[points.count - 1])
        return result
    }

    /// Discrete Fréchet distance (Eiter & Mannila): the shortest leash that
    /// lets two walkers go along both polylines, forwards only.
    static func frechetDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return .infinity }
        var previous = [Double](repeating: 0, count: b.count)
        var current = previous
        for i in 0..<a.count {
            for j in 0..<b.count {
                let d = distance(a[i], b[j])
                switch (i, j) {
                case (0, 0): current[j] = d
                case (0, _): current[j] = max(current[j - 1], d)
                case (_, 0): current[j] = max(previous[0], d)
                default: current[j] = max(min(previous[j], previous[j - 1], current[j - 1]), d)
                }
            }
            swap(&previous, &current)
        }
        return previous[b.count - 1]
    }

    /// Mean absolute turning angle between consecutive segments (radians).
    static func meanTurning(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        var count = 0
        for i in 1..<(points.count - 1) {
            let a = CGVector(dx: points[i].x - points[i - 1].x, dy: points[i].y - points[i - 1].y)
            let b = CGVector(dx: points[i + 1].x - points[i].x, dy: points[i + 1].y - points[i].y)
            guard a.dx != 0 || a.dy != 0, b.dx != 0 || b.dy != 0 else { continue }
            let cross = Double(a.dx * b.dy - a.dy * b.dx)
            let dot = Double(a.dx * b.dx + a.dy * b.dy)
            total += abs(atan2(cross, dot))
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }
}

/// The result card's words: fixed copy picked by stars and the main problem
/// (TECH_SPEC: no generated text). Kind words only; a 0-star stroke is
/// "Almost! Try once more", never "failed".
struct StrokeFeedback: Equatable, Sendable {
    var title: String
    var tip: String

    init(stars: Int, problem: StrokeProblem) {
        switch (stars, problem) {
        case (_, .tooShort):
            title = "Almost! Try once more"
            tip = "Try drawing the whole line, all the way to the end."
        case (_, .tooLong):
            title = "Almost! Try once more"
            tip = "Stop when you reach the end of the dashed line."
        case (0, .wobble):
            title = "Almost! Try once more"
            tip = "Your line got very wobbly. Go slowly and stay on the dashed line."
        case (0, _):
            title = "Almost! Try once more"
            tip = "Start on the blue dot and stay close to the dashed line."
        case (_, .wobble):
            title = "Nice shape!"
            tip = "Your line is a bit wobbly. Try going a little slower for 3 stars."
        case (1, _):
            title = "Good try"
            tip = "Follow the dashed line closely. Slow is fine."
        case (2, _):
            title = "So close"
            tip = "Stay right on the dashed line for 3 stars."
        case (_, .direction):
            title = "Great line"
            tip = "Next time, try starting at the blue dot."
        default:
            title = "Spot on"
            tip = "That's exactly the line. On to the next one."
        }
    }
}
