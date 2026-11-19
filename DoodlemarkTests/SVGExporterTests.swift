import PencilKit
import XCTest
@testable import Doodlemark

/// Structure, determinism and the snapshot. Visual faithfulness is the step 3 gate.
final class SVGExporterTests: XCTestCase {

    // MARK: Snapshot

    /// One known shape + one stroke, compared byte-for-byte with a committed file.
    /// To re-record after an intended change, run tests with
    /// `TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test ...`, review the diff, commit it.
    func testShapeAndStrokeMatchesSnapshot() throws {
        let shape = LogoShape(
            id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 400),
            size: 300, rotation: 0, fill: .first)
        // A straight stroke, moved down 50pt by its transform: the output must show y = 750.
        let stroke = Fixtures.monolineStroke(
            [CGPoint(x: 200, y: 700), CGPoint(x: 500, y: 700), CGPoint(x: 800, y: 700)],
            transform: CGAffineTransform(translationX: 0, y: 50))

        let actual = try SVGExporter.svg(palette: Palettes.starter, shapes: [shape], ink: PKDrawing(strokes: [stroke]), text: nil)
        try assertSnapshot(actual, named: "shape-and-stroke")
    }

    // MARK: Structure

    func testLayerOrderIsShapesInkText() throws {
        let svg = try SVGExporter.svg(
            palette: Palettes.starter,
            shapes: [LogoShape(id: UUID(), kind: .star, center: CGPoint(x: 512, y: 512),
                               size: 200, rotation: 0, fill: .third)],
            ink: PKDrawing(strokes: [Fixtures.monolineStroke([CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 900)])]),
            text: Fixtures.pizzaText())
        let shapes = try XCTUnwrap(svg.range(of: #"<g id="shapes">"#)).lowerBound
        let ink = try XCTUnwrap(svg.range(of: #"<g id="ink""#)).lowerBound
        let text = try XCTUnwrap(svg.range(of: #"<g id="text">"#)).lowerBound
        XCTAssertLessThan(shapes, ink)
        XCTAssertLessThan(ink, text)
        XCTAssertTrue(svg.contains(#"viewBox="0 0 1024.00 1024.00""#))
    }

    func testTextIsExportedAsOutlinesNeverAsTextElement() throws {
        let svg = try SVGExporter.svg(palette: Palettes.starter, shapes: [], ink: PKDrawing(), text: Fixtures.pizzaText())
        XCTAssertFalse(svg.contains("<text"))
        XCTAssertFalse(svg.contains("LilitaOne"))
        XCTAssertTrue(svg.contains(##"<path fill="#1C1B22" d="M"##))
    }

    func testMissingFontThrowsInsteadOfDroppingText() {
        var text = Fixtures.pizzaText()
        text.fontName = "Helvetica-Nope"
        XCTAssertThrowsError(try SVGExporter.svg(palette: Palettes.starter, shapes: [], ink: PKDrawing(), text: text))
    }

    func testEmptyInputHasNoLayerGroups() throws {
        let svg = SVGExporter.svg(ink: PKDrawing())
        XCTAssertFalse(svg.contains("<g"))
    }

    func testOutputIsDeterministic() throws {
        let project = Fixtures.fullProject()
        let drawing = PKDrawing(strokes: [
            Fixtures.monolineStroke([CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 300),
                                     CGPoint(x: 500, y: 600), CGPoint(x: 700, y: 350)])
        ])
        XCTAssertEqual(try SVGExporter.svg(project: project, ink: drawing),
                       try SVGExporter.svg(project: project, ink: drawing))
    }

    // MARK: Strokes

    func testTapExportsAsZeroLengthRoundCapSegment() throws {
        let dot = Fixtures.monolineStroke([CGPoint(x: 300, y: 300)], width: 12)
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: dot))
        XCTAssertTrue(element.contains(#"d="M300.00 300.00 L300.00 300.00""#), element)
        XCTAssertTrue(element.contains(#"stroke-width="20.00""#), element)   // 2·12 − 4
    }

    func testScaledTransformScalesWidthAndPoints() throws {
        let stroke = Fixtures.monolineStroke(
            [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10)], width: 8,
            transform: CGAffineTransform(scaleX: 2, y: 2))
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: stroke))
        XCTAssertTrue(element.contains(#"stroke-width="24.00""#), element)   // (2·8 − 4) · 2
        XCTAssertTrue(element.contains("M20.00 20.00"), element)
        XCTAssertTrue(element.contains("220.00 20.00"), element)
    }

    func testTranslucentInkGetsStrokeOpacity() throws {
        var stroke = Fixtures.monolineStroke([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)])
        stroke.ink = PKInk(.monoline, color: UIColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let element = try XCTUnwrap(SVGExporter.strokeElement(for: stroke))
        XCTAssertTrue(element.contains(##"stroke="#FF0000""##), element)
        XCTAssertTrue(element.contains(#"stroke-opacity="0.50""#), element)
    }

    func testDarkModeInkVariantIsNeverExported() throws {
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        XCTAssertEqual(SVGExporter.inkColor(dynamic).color, HexColor(red: 0, green: 0, blue: 0))
    }

    func testDisplayP3ColorIsConvertedToSRGB() throws {
        let p3Red = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let (color, alpha) = SVGExporter.inkColor(p3Red)
        XCTAssertEqual(color, HexColor(red: 255, green: 0, blue: 0))   // clamped into sRGB
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }

    func testStrokeTooThinToRenderIsSkipped() {
        let hairline = Fixtures.monolineStroke([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)], width: 2)
        XCTAssertNil(SVGExporter.strokeElement(for: hairline))
    }

    // MARK: Simplification

    func testSimplifyKeepsCornersAndDropsCollinearPoints() {
        let line = (0...50).map { CGPoint(x: CGFloat($0) * 2, y: 0) }
        XCTAssertEqual(SVGExporter.simplify(line, tolerance: 0.5), [line.first!, line.last!])

        let corner = (0...20).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
            + (1...20).map { CGPoint(x: 100, y: CGFloat($0) * 5) }
        XCTAssertEqual(SVGExporter.simplify(corner, tolerance: 0.5),
                       [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
    }

    func testSharpCornerStaysSharp() {
        // A "V": at the corner, each handle lies on its own leg, so the point stays sharp.
        let d = SVGExporter.smoothPathData([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 0)])
        XCTAssertEqual(d, "M0.00 0.00 C33.33 66.67 66.67 133.33 100.00 200.00 C133.33 133.33 166.67 66.67 200.00 0.00")
    }

    // MARK: Tiny-segment merge

    func testCornerCurlIsMergedAndTheLegsDontMove() {
        // The step 7 rocket corner: a long leg, a curl of two ~2 pt chords, a long leg.
        let points = [CGPoint(x: 595.27, y: 380), CGPoint(x: 595.81, y: 536.66), CGPoint(x: 595.66, y: 538.70),
                      CGPoint(x: 594.51, y: 539.79), CGPoint(x: 432.37, y: 540.00)]
        // The curl's middle point is 0.64 pt off its shortcut: it goes. Both
        // legs keep their exact end points.
        XCTAssertEqual(SVGExporter.mergeTinySegments(points), [points[0], points[1], points[3], points[4]])
    }

    func testOneTinySegmentAloneIsKept() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 101, y: 1), CGPoint(x: 101, y: 100)]
        XCTAssertEqual(SVGExporter.mergeTinySegments(points), points)
    }

    func testRealTinyLoopIsNeverFlattened() {
        // A 6 pt loop between two long legs: merging would move points > 1 pt.
        let loop = (0...8).map { i -> CGPoint in
            let a = CGFloat(i) / 8 * 2 * .pi
            return CGPoint(x: 100 + 3 * sin(a), y: 100 - 3 + 3 * cos(a))
        }
        let points = [CGPoint(x: 0, y: 100)] + loop + [CGPoint(x: 200, y: 100)]
        XCTAssertEqual(SVGExporter.mergeTinySegments(points), points)
    }

    func testStrokeEndsNeverMove() {
        // Jitter at both ends: the first and last points stay exactly where
        // they were, only the jitter next to them goes.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.2), CGPoint(x: 2, y: 0.1), CGPoint(x: 100, y: 0),
                      CGPoint(x: 100, y: 60), CGPoint(x: 100.6, y: 61.4), CGPoint(x: 100.2, y: 62.8)]
        let merged = SVGExporter.mergeTinySegments(points)
        XCTAssertEqual(merged.first, points.first)
        XCTAssertEqual(merged.last, points.last)
        XCTAssertFalse(merged.contains(CGPoint(x: 1, y: 0.2)))
        XCTAssertFalse(merged.contains(CGPoint(x: 100.6, y: 61.4)))
        XCTAssertTrue(merged.contains(CGPoint(x: 100, y: 0)), "the real corner stays")
    }

    func testLongSegmentsAreUntouched() {
        let zigzag = (0...10).map { CGPoint(x: CGFloat($0) * 20, y: $0.isMultiple(of: 2) ? 0 : 30) }
        XCTAssertEqual(SVGExporter.mergeTinySegments(zigzag), zigzag)
    }

    // MARK: Number formatting

    func testNumbersUseFixedTwoDecimals() {
        XCTAssertEqual(SVGExporter.format(0), "0.00")
        XCTAssertEqual(SVGExporter.format(1024), "1024.00")
        XCTAssertEqual(SVGExporter.format(3.14159), "3.14")
        XCTAssertEqual(SVGExporter.format(7.126), "7.13")
        XCTAssertEqual(SVGExporter.format(-12.5), "-12.50")
        XCTAssertEqual(SVGExporter.format(0.05), "0.05")
        XCTAssertEqual(SVGExporter.format(-0.004), "0.00")     // never "-0.00"
        XCTAssertEqual(SVGExporter.format(.nan), "0.00")
    }

    // MARK: - Snapshot helper

    private func assertSnapshot(_ actual: String, named name: String,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let sourceURL = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Snapshots/\(name).svg")

        if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" {
            try actual.write(to: sourceURL, atomically: true, encoding: .utf8)
            XCTFail("Recorded snapshot \(name).svg. Review it, then run again without RECORD_SNAPSHOTS.",
                    file: file, line: line)
            return
        }

        let bundleURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "svg"),
            "Missing snapshot \(name).svg. Record it with TEST_RUNNER_RECORD_SNAPSHOTS=1.",
            file: file, line: line)
        let expected = try String(contentsOf: bundleURL, encoding: .utf8)
        if actual != expected {
            let attachment = XCTAttachment(string: actual)
            attachment.name = "\(name)-actual.svg"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(actual, expected, "SVG differs from Snapshots/\(name).svg", file: file, line: line)
    }
}
