import CoreGraphics
import Foundation
import PencilKit
import UIKit

/// Builds the logo SVG. A pure function: data in, SVG string out. No file
/// writing, no views, no global state. The same input always gives the same
/// bytes, because every number is written with fixed 2-decimal precision.
///
/// It takes the Ink drawing only. There is no parameter for the Sketch layer,
/// so the Sketch can never end up in an SVG.
///
/// Layer order follows TECH_SPEC: Shapes, then Ink, then Text, in a
/// `0 0 1024 1024` viewBox (canvas space).
///
/// Assumptions the canvas guarantees (CLAUDE.md hard rules): Ink strokes use
/// `.monoline` ink (constant width) and are only removed by the vector eraser,
/// so `stroke.mask` is always nil and pressure never changes the width.
enum SVGExporter {
    static let canvasSize: CGFloat = 1024
    /// Spacing of the dense polyline sampled from each stroke, in canvas points.
    static let sampleSpacing: CGFloat = 2
    /// Ramer–Douglas–Peucker tolerance, in canvas points. 0.5 (the first value
    /// tried) flattened finger-like wobble enough to reach 23% mismatch in one
    /// gate tile; 0.25 brings it to 3% at modest file size. 0.1 gained little more.
    static let simplifyTolerance: CGFloat = 0.25
    /// A turn sharper than this at a simplified point is a corner and stays sharp.
    /// Bends below it are smoothed. Misclassifying a tight curve as a corner
    /// costs at most the RDP tolerance, so the exact value isn't critical.
    static let cornerAngle: CGFloat = .pi / 4
    /// A stroke shorter than this is a tap and exports as a round dot.
    static let dotLength: CGFloat = 0.5
    /// PencilKit draws a monoline stroke `slope · w + offset` points thick, where
    /// `w` is `PKStrokePoint.size.width`. It's an affine law, not a ratio:
    /// measured 4 → 4, 8 → 12, 16 → 28, 32 → 60, and w ≤ 2 draws nothing.
    /// A scaled `stroke.transform` multiplies the result. Force, nib height and
    /// point spacing don't matter. Documented by `MonolineWidthTests`.
    static let monolineWidthSlope: CGFloat = 2
    static let monolineWidthOffset: CGFloat = -4

    /// The thickness PencilKit actually renders for a monoline point width (before transform scale).
    static func renderedMonolineWidth(pointWidth: CGFloat) -> CGFloat {
        max(0, monolineWidthSlope * pointWidth + monolineWidthOffset)
    }

    static func svg(project: Project, ink: PKDrawing) throws(GlyphPaths.Failure) -> String {
        try svg(shapes: project.shapes, ink: ink, text: project.text)
    }

    static func svg(shapes: [LogoShape], ink: PKDrawing, text: LogoText?) throws(GlyphPaths.Failure) -> String {
        let size = format(canvasSize)
        var lines = [
            #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(size)" height="\#(size)" viewBox="0 0 \#(size) \#(size)">"#
        ]

        if !shapes.isEmpty {
            lines.append(#"  <g id="shapes">"#)
            for shape in shapes {
                let d = pathData(ShapeGeometry.path(for: shape))
                lines.append(#"    <path fill="\#(shape.fill.hexString)" d="\#(d)"/>"#)
            }
            lines.append("  </g>")
        }

        let strokeElements = ink.strokes.compactMap(strokeElement(for:))
        if !strokeElements.isEmpty {
            lines.append(#"  <g id="ink" fill="none" stroke-linecap="round" stroke-linejoin="round">"#)
            lines.append(contentsOf: strokeElements.map { "    " + $0 })
            lines.append("  </g>")
        }

        if let text, !text.string.isEmpty {
            let outline = try GlyphPaths.path(for: text)
            if !outline.isEmpty {
                lines.append(#"  <g id="text">"#)
                lines.append(#"    <path fill="\#(text.fill.hexString)" d="\#(pathData(outline))"/>"#)
                lines.append("  </g>")
            }
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Ink strokes

    /// One `<path>` for one monoline stroke, or nil if PencilKit wouldn't draw it
    /// (no points, or too thin to render).
    static func strokeElement(for stroke: PKStroke) -> String? {
        let transform = stroke.transform
        var points: [CGPoint] = []
        var widths: [CGFloat] = []
        for point in stroke.path.interpolatedPoints(by: .distance(sampleSpacing)) {
            points.append(point.location.applying(transform))   // always apply stroke.transform
            widths.append(point.size.width)
        }
        guard let first = points.first else { return nil }

        // Monoline width is constant, so the median is just robust against odd samples.
        // A scaled transform scales the rendered width too.
        let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
        let width = renderedMonolineWidth(pointWidth: median(widths)) * scale
        guard width > 0 else { return nil }   // PencilKit draws nothing for it either

        let d: String
        if polylineLength(points) < dotLength {
            // A tap. A zero-length segment with round caps renders as a dot;
            // a lone "M" would render nothing.
            d = "M\(pair(first)) L\(pair(first))"
        } else {
            d = smoothPathData(simplify(points, tolerance: simplifyTolerance))
        }

        let (color, alpha) = inkColor(stroke.ink.color)
        var attributes = #"stroke="\#(color.hexString)" stroke-width="\#(format(width))""#
        if alpha < 0.995 {
            attributes += #" stroke-opacity="\#(format(alpha))""#
        }
        return #"<path \#(attributes) d="\#(d)"/>"#
    }

    /// Resolves the ink color for light mode (never the dark-mode variant) and converts it to sRGB.
    static func inkColor(_ color: UIColor) -> (color: HexColor, alpha: CGFloat) {
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        return HexColor.sRGB(from: light.cgColor) ?? (HexColor(red: 0, green: 0, blue: 0), 1)
    }

    /// Cubic Béziers through the simplified points.
    ///
    /// - Smooth points get a Catmull-Rom tangent (the direction from the previous
    ///   to the next point).
    /// - **Corners** (the path turns more than `cornerAngle` at a point) get
    ///   one-sided tangents instead, so the stroke keeps its sharp point. Without
    ///   this, RDP leaves a corner between two long straight legs and the averaged
    ///   tangent turns a "V" into a "U" (caught by the zig-zag gate fixture).
    /// - Handle length at a point is a third of the *shorter* neighbouring chord,
    ///   so a long straight leg next to a short bend stays straight instead of bulging.
    static func smoothPathData(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var d = "M\(pair(first))"
        guard points.count > 2 else {
            if points.count == 2 { d += " L\(pair(points[1]))" }
            return d
        }

        let n = points.count
        var tangentIn = [CGPoint](repeating: .zero, count: n)    // direction arriving at point i
        var tangentOut = [CGPoint](repeating: .zero, count: n)   // direction leaving point i
        var handle = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let previous = points[max(i - 1, 0)]
            let next = points[min(i + 1, n - 1)]
            let incoming = unit(points[i] - previous, fallback: next - points[i])
            let outgoing = unit(next - points[i], fallback: points[i] - previous)
            let isCorner = i > 0 && i < n - 1 && turnAngle(incoming, outgoing) > cornerAngle
            if isCorner {
                tangentIn[i] = incoming
                tangentOut[i] = outgoing
            } else {
                let smooth = unit(next - previous, fallback: outgoing)
                tangentIn[i] = smooth
                tangentOut[i] = smooth
            }
            let chordIn = i > 0 ? distance(previous, points[i]) : .infinity
            let chordOut = i < n - 1 ? distance(points[i], next) : .infinity
            handle[i] = min(chordIn, chordOut) / 3
        }

        for i in 0..<(n - 1) {
            let c1 = points[i] + tangentOut[i] * handle[i]
            let c2 = points[i + 1] - tangentIn[i + 1] * handle[i + 1]
            d += " C\(pair(c1)) \(pair(c2)) \(pair(points[i + 1]))"
        }
        return d
    }

    /// Angle between two unit directions, 0…π.
    private static func turnAngle(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        acos(min(max(a.x * b.x + a.y * b.y, -1), 1))
    }

    /// Ramer–Douglas–Peucker, iterative (long strokes would recurse deeply).
    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]

        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance: CGFloat = 0
            var index = start
            for i in (start + 1)..<end {
                let d = distanceFromSegment(points[i], points[start], points[end])
                if d > maxDistance {
                    maxDistance = d
                    index = i
                }
            }
            if maxDistance > tolerance {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    // MARK: - CGPath → SVG path data

    /// Serialises a CGPath (shapes, glyph outlines) as SVG path data.
    static func pathData(_ path: CGPath) -> String {
        var commands: [String] = []
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                commands.append("M\(pair(p[0]))")
            case .addLineToPoint:
                commands.append("L\(pair(p[0]))")
            case .addQuadCurveToPoint:
                commands.append("Q\(pair(p[0])) \(pair(p[1]))")
            case .addCurveToPoint:
                commands.append("C\(pair(p[0])) \(pair(p[1])) \(pair(p[2]))")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                break
            }
        }
        return commands.joined(separator: " ")
    }

    // MARK: - Number formatting

    /// Fixed 2-decimal, locale-independent (always "."), never "-0.00".
    static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "0.00" }
        let hundredths = Int((Double(value) * 100).rounded())
        let magnitude = abs(hundredths)
        let fraction = magnitude % 100
        let sign = hundredths < 0 ? "-" : ""
        return "\(sign)\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    private static func pair(_ point: CGPoint) -> String {
        "\(format(point.x)) \(format(point.y))"
    }

    // MARK: - Geometry helpers

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func distanceFromSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared, 0), 1)
        return distance(p, a + ab * t)
    }

    private static func unit(_ v: CGPoint, fallback: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        if length > 0 { return v * (1 / length) }
        let fallbackLength = hypot(fallback.x, fallback.y)
        return fallbackLength > 0 ? fallback * (1 / fallbackLength) : .zero
    }
}

// Small vector maths on CGPoint, private to the exporter.
private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
