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
    /// Ramer–Douglas–Peucker tolerance, in canvas points.
    static let simplifyTolerance: CGFloat = 0.5
    /// A stroke shorter than this is a tap and exports as a round dot.
    static let dotLength: CGFloat = 0.5

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

    /// One `<path>` for one monoline stroke, or nil if the stroke has no points.
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
        let width = median(widths) * scale

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

    /// Cubic Béziers through the simplified points. Tangent directions come from
    /// Catmull-Rom (neighbouring points), but each handle is a third of its own
    /// segment's length. Plain uniform Catmull-Rom overshoots where RDP leaves a
    /// long segment next to short ones, and this stays inside the hull instead.
    static func smoothPathData(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var d = "M\(pair(first))"
        guard points.count > 2 else {
            if points.count == 2 { d += " L\(pair(points[1]))" }
            return d
        }

        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let third = distance(p1, p2) / 3
            let t1 = unit(p2 - p0, fallback: p2 - p1)
            let t2 = unit(p3 - p1, fallback: p2 - p1)
            let c1 = p1 + t1 * third
            let c2 = p2 - t2 * third
            d += " C\(pair(c1)) \(pair(c2)) \(pair(p2))"
        }
        return d
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
