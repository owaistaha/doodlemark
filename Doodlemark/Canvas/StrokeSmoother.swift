import PencilKit

/// "Smooth my lines" for the Ink layer: after a stroke ends it is replaced by
/// a smoothed copy, in the same undo step.
///
/// Rules: endpoints never move, corners sharper than 45° stay sharp (the
/// exporter's corner test), dots are untouched, and only point locations
/// change (width, timing and the rest of each point are kept).
///
/// Learn mode scores the RAW stroke, before smoothing (TECH_SPEC).
enum StrokeSmoother {
    /// Gaussian width along the stroke, in canvas points. Finger wobble is a
    /// few points across; letter-sized curves are tens of points.
    static let sigma: CGFloat = 5
    /// Corner finding runs on a Ramer–Douglas–Peucker simplification this
    /// coarse, so finger wobble (±1–2 pt) doesn't count as corners. The angle
    /// test itself is the exporter's (`SVGExporter.isCorner`, 45°).
    static let cornerSimplifyTolerance: CGFloat = 2
    /// Strokes shorter than this are dots and stay as they are.
    static let minimumLength: CGFloat = 1

    static func smoothed(_ stroke: PKStroke) -> PKStroke {
        let points = stroke.path.map(\.location)
        let smoothedLocations = smoothed(points)
        guard smoothedLocations != points else { return stroke }
        let controlPoints = zip(stroke.path, smoothedLocations).map { original, location in
            PKStrokePoint(location: location, timeOffset: original.timeOffset, size: original.size,
                          opacity: original.opacity, force: original.force, azimuth: original.azimuth,
                          altitude: original.altitude, secondaryScale: original.secondaryScale)
        }
        var copy = stroke
        copy.path = PKStrokePath(controlPoints: controlPoints, creationDate: stroke.path.creationDate)
        return copy
    }

    /// The smoothed polyline: same count, pinned points unchanged.
    static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3, length(of: points) >= minimumLength else { return points }

        // Pinned: both ends and every corner.
        var pinned = [0, points.count - 1]
        let kept = SVGExporter.simplifiedIndices(points, tolerance: cornerSimplifyTolerance)
        if kept.count >= 3 {
            for k in 1..<(kept.count - 1)
            where SVGExporter.isCorner(previous: points[kept[k - 1]], point: points[kept[k]], next: points[kept[k + 1]]) {
                pinned.append(kept[k])
            }
        }
        pinned = Array(Set(pinned)).sorted()

        // Gaussian average along the stroke, one run between pinned points at
        // a time. Each run is extended by odd reflection through its pinned
        // ends (p ↦ 2·end − p), so the average stays balanced right up to a
        // pinned point: straight runs don't move at all, and nothing slides
        // away from a corner.
        var result = points
        let reach = 3 * sigma
        for (start, end) in zip(pinned, pinned.dropFirst()) where end - start >= 2 {
            let run = Array(points[start...end])
            var arc = [CGFloat](repeating: 0, count: run.count)
            for k in 1..<run.count {
                arc[k] = arc[k - 1] + hypot(run[k].x - run[k - 1].x, run[k].y - run[k - 1].y)
            }
            let first = run[0], last = run[run.count - 1], total = arc[run.count - 1]
            var samples: [(arc: CGFloat, point: CGPoint)] = []
            for k in stride(from: run.count - 1, through: 1, by: -1) {
                samples.append((-arc[k], CGPoint(x: 2 * first.x - run[k].x, y: 2 * first.y - run[k].y)))
            }
            samples += zip(arc, run).map { ($0, $1) }
            for k in stride(from: run.count - 2, through: 0, by: -1) {
                samples.append((2 * total - arc[k], CGPoint(x: 2 * last.x - run[k].x, y: 2 * last.y - run[k].y)))
            }

            for k in 1..<(run.count - 1) {
                var sum = CGPoint.zero
                var weightSum: CGFloat = 0
                for sample in samples where abs(sample.arc - arc[k]) <= reach {
                    let d = sample.arc - arc[k]
                    let w = exp(-(d * d) / (2 * sigma * sigma))
                    sum.x += sample.point.x * w
                    sum.y += sample.point.y * w
                    weightSum += w
                }
                result[start + k] = CGPoint(x: sum.x / weightSum, y: sum.y / weightSum)
            }
        }
        return result
    }

    private static func length(of points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
}
